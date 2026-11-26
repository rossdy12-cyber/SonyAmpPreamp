import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { generateKeyPairSync, createPrivateKey } from 'node:crypto';
import { createPushRelay, createProviderJWT, verifyProfileEntitlements } from '../src/push-relay.mjs';

const relayToken = 'private-relay-test-token-with-more-than-32-characters';
const validEntitlements = { 'application-identifier': 'G42YL9QS8W.com.ross.forgelink', 'com.apple.developer.team-identifier': 'G42YL9QS8W', 'aps-environment': 'development' };

async function makeRelay(t, options = {}) {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'forgelink-push-'));
  const relay = await createPushRelay({
    baseDir: directory,
    env: { NODE_ENV: 'test', FORGELINK_PUSH_TOKEN: relayToken, FORGELINK_PUSH_DEVICES: path.join(directory, 'data', 'push-devices.json'), ...options.env },
    sendAPNs: options.sendAPNs
  });
  await new Promise(resolve => relay.server.listen(0, '127.0.0.1', resolve));
  const base = `http://127.0.0.1:${relay.server.address().port}`;
  const api = async (url, body, authorized = true) => {
    const response = await fetch(base + url, {
      method: body === undefined ? 'GET' : url === '/register' ? 'PATCH' : 'POST',
      headers: { ...(authorized ? { Authorization: `Bearer ${relayToken}` } : {}), 'Content-Type': 'application/json' },
      body: body === undefined ? undefined : JSON.stringify(body)
    });
    return { status: response.status, body: await response.json() };
  };
  t.after(async () => { await relay.close(); await rm(directory, { recursive: true, force: true }); });
  return { api, relay, directory };
}

test('profile entitlement gate requires the exact bundle and APNs environment', () => {
  assert.equal(verifyProfileEntitlements(validEntitlements, { bundleId: 'com.ross.forgelink', teamId: 'G42YL9QS8W', environment: 'development' }), true);
  assert.throws(() => verifyProfileEntitlements(validEntitlements, { bundleId: 'com.ross.nocturne', teamId: 'G42YL9QS8W', environment: 'development' }), /application identifier/);
  assert.throws(() => verifyProfileEntitlements({ ...validEntitlements, 'com.apple.developer.team-identifier': 'OTHERTEAM00' }, { bundleId: 'com.ross.forgelink', teamId: 'G42YL9QS8W', environment: 'development' }), /team entitlement/);
  assert.throws(() => verifyProfileEntitlements(validEntitlements, { bundleId: 'com.ross.forgelink', teamId: 'G42YL9QS8W', environment: 'production' }), /APS environment/);
});

test('relay stays disabled by default and refuses registration/notification', async t => {
  const f = await makeRelay(t);
  assert.equal(f.relay.settings.apnsEnabled, false);
  const health = await fetch(`http://127.0.0.1:${f.relay.server.address().port}/health`);
  assert.equal(health.status, 200);
  assert.deepEqual(await health.json(), { ok: true, apnsEnabled: false });
  assert.equal((await f.api('/register', { deviceToken: 'ab'.repeat(32), bundleId: 'com.ross.forgelink', enabled: true })).status, 503);
  assert.equal((await f.api('/notify', { runId: 'r1', status: 'succeeded' })).status, 503);
});

test('relay requires complete APNs configuration before enabling', async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'forgelink-push-config-'));
  try {
    await assert.rejects(createPushRelay({ baseDir: directory, env: { FORGELINK_PUSH_TOKEN: relayToken, APNS_ENABLED: 'true' } }), /Incomplete ForgeLink APNs/);
  } finally { await rm(directory, { recursive: true, force: true }); }
});

test('enabled relay delivers completion alerts only to registered devices', async t => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'forgelink-push-enabled-'));
  const { privateKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  const keyPath = path.join(directory, 'apns-key.p8');
  const profilePath = path.join(directory, 'profile.mobileprovision');
  await writeFile(keyPath, privateKey.export({ type: 'pkcs8', format: 'pem' }), { mode: 0o600 });
  const { execFileSync } = await import('node:child_process');
  const profileKey = generateKeyPairSync('rsa', { modulusLength: 2048 });
  const profileKeyPath = path.join(directory, 'profile-key.pem');
  const profileCertPath = path.join(directory, 'profile-cert.pem');
  const profilePlistPath = path.join(directory, 'profile.plist');
  await writeFile(profileKeyPath, profileKey.privateKey.export({ type: 'pkcs8', format: 'pem' }), { mode: 0o600 });
  const profileCert = execFileSync('openssl', ['req', '-x509', '-new', '-key', profileKeyPath, '-subj', '/CN=ForgeLink Test Profile/', '-addext', 'basicConstraints=critical,CA:TRUE', '-days', '1']);
  await writeFile(profileCertPath, profileCert);
  const caPath = path.join(directory, 'profile-ca.pem');
  await writeFile(caPath, profileCert);
  const profilePlist = Buffer.from('<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>Entitlements</key><dict><key>application-identifier</key><string>G42YL9QS8W.com.ross.forgelink</string><key>com.apple.developer.team-identifier</key><string>G42YL9QS8W</string><key>aps-environment</key><string>development</string></dict><key>TeamIdentifier</key><array><string>G42YL9QS8W</string></array><key>ExpirationDate</key><date>2099-01-01T00:00:00Z</date></dict></plist>');
  await writeFile(profilePlistPath, profilePlist);
  const signedProfile = execFileSync('openssl', ['cms', '-sign', '-binary', '-nodetach', '-noattr', '-signer', profileCertPath, '-inkey', profileKeyPath, '-in', profilePlistPath, '-outform', 'DER']);
  await writeFile(profilePath, signedProfile, { mode: 0o600 });
  const sent = [];
  const relay = await createPushRelay({
    baseDir: directory,
    env: { NODE_ENV: 'test', FORGELINK_PUSH_TOKEN: relayToken, APNS_ENABLED: 'true', APNS_TEAM_ID: 'G42YL9QS8W', APNS_KEY_ID: 'AB12CD34EF', APNS_BUNDLE_ID: 'com.ross.forgelink', APNS_ENVIRONMENT: 'development', APNS_KEY_FILE: keyPath, APNS_PROFILE_FILE: profilePath, APNS_PROFILE_CA_FILE: caPath, FORGELINK_PUSH_DEVICES: path.join(directory, 'data', 'push-devices.json') },
    sendAPNs: async (settings, device, payload, jwt) => { sent.push({ settings, device, payload: JSON.parse(payload), jwt }); return { status: 200, reason: '' }; }
  });
  await new Promise(resolve => relay.server.listen(0, '127.0.0.1', resolve));
  t.after(async () => { await relay.close(); await rm(directory, { recursive: true, force: true }); });
  const base = `http://127.0.0.1:${relay.server.address().port}`;
  const call = (url, body) => fetch(base + url, { method: url === '/register' ? 'PATCH' : 'POST', headers: { Authorization: `Bearer ${relayToken}`, 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
  const device = 'ef'.repeat(32);
  assert.equal((await call('/register', { deviceToken: device, bundleId: 'com.ross.forgelink', enabled: true })).status, 200);
  const result = await call('/notify', { runId: 'run_1', projectId: 'test', title: 'ForgeLink · Claude', body: 'Task complete', status: 'succeeded' });
  assert.equal(result.status, 200);
  assert.deepEqual(await result.json(), { accepted: true, apnsEnabled: true, delivered: 1 });
  assert.equal(sent.length, 1);
  assert.equal(sent[0].device, device);
  assert.equal(sent[0].settings.environment, 'development');
  assert.equal(sent[0].payload.aps.alert.body, 'Task complete');
  const [header, claims] = sent[0].jwt.split('.').slice(0, 2).map(value => JSON.parse(Buffer.from(value, 'base64url')));
  assert.deepEqual(header, { alg: 'ES256', kid: 'AB12CD34EF' });
  assert.equal(claims.iss, 'G42YL9QS8W');
  assert.equal(createPrivateKey(await readFile(keyPath, 'utf8')).asymmetricKeyType, 'ec');
});

test('provider JWT is formed with ES256 and carries the APNs issuer/key identifiers', () => {
  const { privateKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  const jwt = createProviderJWT({ teamId: 'G42YL9QS8W', keyId: 'AB12CD34EF', key: privateKey.export({ type: 'pkcs8', format: 'pem' }) }, 1000);
  const [encodedHeader, encodedClaims, encodedSignature] = jwt.split('.');
  assert.deepEqual(JSON.parse(Buffer.from(encodedHeader, 'base64url')), { alg: 'ES256', kid: 'AB12CD34EF' });
  assert.deepEqual(JSON.parse(Buffer.from(encodedClaims, 'base64url')), { iss: 'G42YL9QS8W', iat: 1000 });
  assert.equal(Buffer.from(encodedSignature, 'base64url').length, 64);
});
