import http from 'node:http';
import http2 from 'node:http2';
import { createHash, timingSafeEqual, createPrivateKey, sign } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { mkdir, readFile, rename, writeFile } from 'node:fs/promises';
import path from 'node:path';

const MAX_BODY = 32 * 1024;
const digest = value => createHash('sha256').update(value).digest();
const validDeviceToken = value => typeof value === 'string' && /^[a-fA-F0-9]{64,128}$/.test(value);

async function readJsonBody(request) {
  let raw = '';
  for await (const chunk of request) {
    raw += chunk.toString();
    if (Buffer.byteLength(raw) > MAX_BODY) throw Object.assign(new Error('Request is too large.'), { status: 413 });
  }
  try { return JSON.parse(raw); }
  catch { throw Object.assign(new Error('Invalid JSON.'), { status: 400 }); }
}

export function verifyProfileEntitlements(entitlements, { bundleId, teamId, environment }) {
  const allowed = entitlements?.Entitlements || entitlements;
  if (allowed?.['application-identifier'] !== `${teamId}.${bundleId}`) throw new Error('The provisioning profile application identifier does not match ForgeLink.');
  if (allowed?.['com.apple.developer.team-identifier'] !== teamId) throw new Error('The provisioning profile team entitlement does not match ForgeLink.');
  if (allowed?.['aps-environment'] !== environment) throw new Error('The provisioning profile APS environment does not match the selected APNs environment.');
  return true;
}

export function createProviderJWT({ teamId, keyId, key }, now = Math.floor(Date.now() / 1000)) {
  const b64 = value => Buffer.from(value).toString('base64url');
  const header = b64(JSON.stringify({ alg: 'ES256', kid: keyId }));
  const claims = b64(JSON.stringify({ iss: teamId, iat: now }));
  const input = `${header}.${claims}`;
  const der = sign('sha256', Buffer.from(input), createPrivateKey(key));
  let offset = 0;
  const readLength = () => { const first = der[offset++]; if (first < 128) return first; const size = first & 127; let length = 0; for (let i = 0; i < size; i++) length = length * 256 + der[offset++]; return length; };
  if (der[offset++] !== 0x30) throw new Error('Invalid APNs signing signature.');
  const sequenceLength = readLength();
  if (offset + sequenceLength !== der.length) throw new Error('Invalid APNs signing signature.');
  const readInteger = () => {
    if (der[offset++] !== 0x02) throw new Error('Invalid APNs signing signature.');
    const size = readLength();
    const value = der.subarray(offset, offset + size);
    offset += size;
    return value;
  };
  const r = readInteger();
  const s = readInteger();
  const fixed = value => {
    while (value.length > 32 && value[0] === 0) value = value.subarray(1);
    if (value.length > 32) throw new Error('APNs signature integer is oversized.');
    return value.length === 32 ? value : Buffer.concat([Buffer.alloc(32 - value.length), value]);
  };
  return `${input}.${Buffer.concat([fixed(r), fixed(s)]).toString('base64url')}`;
}

export function createAPNsHTTP2Sender({ timeoutMs = 12000 } = {}) {
  return (settings, deviceToken, payload, providerJWT) => new Promise((resolve, reject) => {
    const host = settings.environment === 'development' ? 'https://api.sandbox.push.apple.com' : 'https://api.push.apple.com';
    const session = http2.connect(host);
    const request = session.request({ ':method': 'POST', ':path': `/3/device/${deviceToken}`, authorization: `bearer ${providerJWT}`, 'apns-topic': settings.bundleId, 'apns-push-type': 'alert', 'apns-priority': '10', 'content-type': 'application/json' });
    const timer = setTimeout(() => request.destroy(new Error('APNs request timed out.')), timeoutMs);
    const response = { status: 0, reason: '' };
    request.on('response', headers => { response.status = Number(headers[':status'] || 0); });
    request.setEncoding('utf8');
    request.on('data', chunk => { if (chunk && response.reason.length < 2048) response.reason += chunk; });
    request.on('error', error => { clearTimeout(timer); session.destroy(); reject(error); });
    request.on('end', () => { clearTimeout(timer); session.close(); resolve(response); });
    request.end(payload);
  });
}

async function readPushToken(env) {
  const token = env.FORGELINK_PUSH_TOKEN || (env.FORGELINK_PUSH_TOKEN_FILE ? (await readFile(env.FORGELINK_PUSH_TOKEN_FILE, 'utf8')).trim() : '');
  if (!token || token.length < 32) throw new Error('Configure a private FORGELINK_PUSH_TOKEN_FILE containing at least 32 random characters.');
  return token;
}

async function verifyAppleProfile(profilePath, { allowTestJSON = false, securePermissions = true, caFile = '/etc/ssl/certs/ca-certificates.crt' } = {}) {
  if (allowTestJSON && path.extname(profilePath).toLowerCase() === '.json') {
    const profile = JSON.parse(await readFile(profilePath, 'utf8'));
    return { entitlements: profile.Entitlements || profile.entitlements, teamIdentifiers: profile.TeamIdentifier || profile.teamIdentifiers || [], expires: profile.ExpirationDate || profile.expires || null };
  }
  const profileStat = await import('node:fs/promises').then(({ stat }) => stat(profilePath));
  if (securePermissions && (profileStat.mode & 0o077) !== 0) throw new Error('ForgeLink provisioning profile permissions must deny all group and world access.');
  const data = await readFile(profilePath);
  const verified = spawnSync('openssl', ['cms', '-verify', '-inform', 'DER', '-binary', '-purpose', 'any', '-CAfile', caFile], { input: data, maxBuffer: 2 * 1024 * 1024, timeout: 10000 });
  if (verified.status !== 0) throw new Error('Apple provisioning profile signature verification failed.');
  const parsed = spawnSync('python', ['-c', 'import sys,plistlib,json;p=plistlib.loads(sys.stdin.buffer.read());print(json.dumps({"entitlements":p.get("Entitlements",{}),"teamIdentifiers":p.get("TeamIdentifier",[]),"expires":p.get("ExpirationDate").isoformat() if p.get("ExpirationDate") else None}))'], { input: verified.stdout, encoding: 'utf8', maxBuffer: 512 * 1024, timeout: 5000 });
  if (parsed.status !== 0) throw new Error('Unable to parse the Apple provisioning profile.');
  return JSON.parse(parsed.stdout);
}

export async function createPushRelay({ env = process.env, baseDir = process.cwd(), sendAPNs = createAPNsHTTP2Sender() } = {}) {
  const token = await readPushToken(env);
  const enabled = env.APNS_ENABLED === 'true';
  let settings = null;
  if (enabled) {
    const teamId = env.APNS_TEAM_ID || '';
    const keyId = env.APNS_KEY_ID || '';
    const bundleId = env.APNS_BUNDLE_ID || '';
    const keyFile = env.APNS_KEY_FILE || '';
    const profileFile = env.APNS_PROFILE_FILE || '';
    const environment = env.APNS_ENVIRONMENT || '';
    if (teamId !== 'G42YL9QS8W' || bundleId !== 'com.ross.forgelink' || !/^[A-Z0-9]{10}$/.test(keyId) || !['development', 'production'].includes(environment) || !keyFile || !profileFile) throw new Error('Incomplete ForgeLink APNs server configuration.');
    if (env.NODE_ENV !== 'test' && env.FORGELINK_USE_DEDICATED_APNS_KEY !== 'true') throw new Error('Refusing APNs delivery until a ForgeLink-specific provider key is configured.');
    const profile = await verifyAppleProfile(profileFile, { allowTestJSON: env.NODE_ENV === 'test', securePermissions: env.NODE_ENV !== 'test', caFile: env.APNS_PROFILE_CA_FILE || '/etc/ssl/certs/ca-certificates.crt' });
    verifyProfileEntitlements(profile.entitlements, { bundleId, teamId, environment });
    if (!profile.teamIdentifiers.includes(teamId)) throw new Error('The provisioning profile is not issued to the ForgeLink Apple Developer team.');
    if (!profile.expires || Date.parse(profile.expires) <= Date.now()) throw new Error('The ForgeLink push provisioning profile has expired.');
    const keyStat = await import('node:fs/promises').then(({ stat }) => stat(keyFile));
    if (env.NODE_ENV !== 'test' && (keyStat.mode & 0o077) !== 0) throw new Error('ForgeLink APNs key permissions must deny all group and world access.');
    const key = await readFile(keyFile, 'utf8');
    createPrivateKey(key);
    settings = { teamId, keyId, bundleId, environment, key };
  }

  const devicesFile = path.resolve(baseDir, env.FORGELINK_PUSH_DEVICES || './data/push-devices.json');
  await mkdir(path.dirname(devicesFile), { recursive: true, mode: 0o700 });
  let devices = new Set();
  try {
    const stored = JSON.parse(await readFile(devicesFile, 'utf8'));
    if (!Array.isArray(stored)) throw new Error('Invalid device list.');
    devices = new Set(stored.filter(validDeviceToken).map(value => value.toLowerCase()));
  } catch (error) { if (error.code !== 'ENOENT') throw new Error('Unable to load the ForgeLink push device list.'); }
  let saving = Promise.resolve();
  const persist = () => {
    const json = JSON.stringify([...devices]);
    const operation = saving.then(async () => { await writeFile(`${devicesFile}.tmp`, json, { mode: 0o600 }); await rename(`${devicesFile}.tmp`, devicesFile); });
    saving = operation.catch(() => {});
    return operation;
  };
  let cachedJWT = '';
  let cachedAt = 0;
  const jwt = () => { const now = Math.floor(Date.now() / 1000); if (!cachedJWT || now - cachedAt >= 2400) { cachedJWT = createProviderJWT(settings); cachedAt = now; } return cachedJWT; };

  const server = http.createServer(async (request, response) => {
    response.setHeader('Content-Type', 'application/json; charset=utf-8');
    response.setHeader('Cache-Control', 'no-store');
    response.setHeader('X-Content-Type-Options', 'nosniff');
    const send = (status, body) => { response.writeHead(status); response.end(JSON.stringify(body)); };
    try {
      if (request.method === 'GET' && request.url === '/health') { send(200, { ok: true, apnsEnabled: Boolean(settings) }); return; }
      const supplied = (request.headers.authorization || '').replace(/^Bearer /, '');
      if (!timingSafeEqual(digest(supplied), digest(token))) { send(401, { error: 'Unauthorized.' }); return; }
      if (request.method === 'PATCH' && request.url === '/register') {
        const input = await readJsonBody(request);
        if (!validDeviceToken(input.deviceToken) || input.bundleId !== 'com.ross.forgelink' || typeof input.enabled !== 'boolean') { send(400, { error: 'Invalid ForgeLink APNs registration.' }); return; }
        if (!input.enabled && !settings && devices.has(input.deviceToken.toLowerCase())) { devices.delete(input.deviceToken.toLowerCase()); await persist(); }
        if (input.enabled && !settings) { send(503, { error: 'Push is disabled until the matching ForgeLink signed profile authorizes APNs.' }); return; }
        if (input.enabled) devices.add(input.deviceToken.toLowerCase()); else devices.delete(input.deviceToken.toLowerCase());
        await persist();
        send(200, { enabled: input.enabled, registered: input.enabled, apnsEnabled: Boolean(settings) });
        return;
      }
      if (request.method !== 'POST' || request.url !== '/notify') { send(404, { error: 'Not found.' }); return; }
      if (!settings) { send(503, { error: 'Push is disabled until the matching ForgeLink signed profile authorizes APNs.' }); return; }
      const input = await readJsonBody(request);
      if (typeof input.runId !== 'string' || !['succeeded', 'failed'].includes(input.status)) { send(400, { error: 'Invalid task notification.' }); return; }
      const payload = JSON.stringify({ aps: { alert: { title: String(input.title || 'ForgeLink').slice(0, 80), body: String(input.body || '').slice(0, 220) }, sound: 'default' }, runId: input.runId, projectId: String(input.projectId || ''), status: input.status });
      const results = await Promise.all([...devices].map(async device => {
        try {
          const result = await sendAPNs(settings, device, payload, jwt());
          if (result.status === 410 || result.status === 400 && result.reason.includes('BadDeviceToken')) devices.delete(device);
          return result.status === 200;
        } catch { return false; }
      }));
      await persist();
      send(200, { accepted: true, apnsEnabled: true, delivered: results.filter(Boolean).length });
    } catch (error) {
      if (!response.headersSent) send(error.status || 500, { error: error.status ? error.message : 'Push service error. Check restricted server logs.' });
    }
  });
  return { server, settings: { apnsEnabled: Boolean(settings) }, async close() { if (server.listening) await new Promise(resolve => server.close(resolve)); await saving; } };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const relay = await createPushRelay();
  relay.server.listen(Number(process.env.PORT || 8788), process.env.HOST || '0.0.0.0', () => console.log(`ForgeLink push relay running (APNs enabled: ${relay.settings.apnsEnabled}).`));
}
