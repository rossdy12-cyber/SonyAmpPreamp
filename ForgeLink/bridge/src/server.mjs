import http from 'node:http';
import { createHash, randomUUID, timingSafeEqual, createHmac } from 'node:crypto';
import { spawn } from 'node:child_process';
import { readFile, writeFile, mkdir, rename, realpath, stat } from 'node:fs/promises';
import path from 'node:path';

const MAX_OUTPUT = 512 * 1024;
const MAX_RUNS = 100;
const terminal = new Set(['succeeded', 'failed', 'cancelled', 'interrupted', 'dispatched']);
const threadRootID = (runs, run) => {
  const visited = new Set();
  let current = run;
  while (current && !visited.has(current.id)) {
    visited.add(current.id);
    if (!current.parentRunId) return current.id;
    current = runs.get(current.parentRunId);
  }
  return run.id;
};
const digest = value => createHash('sha256').update(value).digest();
const braced = (template, variables) => template.replace(/\{([A-Za-z0-9_]+)\}/g, (whole, key) => Object.hasOwn(variables, key) ? variables[key] : whole);
const validID = value => typeof value === 'string' && /^[a-zA-Z0-9_-]{1,80}$/.test(value);
const validDeviceToken = value => typeof value === 'string' && /^[a-fA-F0-9]{64,128}$/.test(value);
async function readJsonBody(req, maximum) {
  let raw = '';
  for await (const chunk of req) {
    raw += chunk.toString();
    if (Buffer.byteLength(raw) > maximum) throw Object.assign(new Error('Request is too large.'), { status: 413 });
  }
  try { return JSON.parse(raw); } catch { throw Object.assign(new Error('Invalid JSON.'), { status: 400 }); }
}
export function buildAgentArguments(agent, prompt, sessionId, continuing = false) {
  const configured = continuing ? agent.resumeArgs : agent.args;
  if (!Array.isArray(configured)) throw new Error('The agent has no configured command arguments for this session.');
  return configured.flatMap(arg => {
    if (arg === '{prompt}') return [prompt];
    if (arg === '{sessionId}') return [sessionId];
    return [arg];
  });
}
export function extractAgentResponse(stdout, format = 'text', provider = 'claude') {
  if (format !== 'json') return { output: stdout, sessionId: null };
  const lines = String(stdout).split(/\r?\n/).map(line => line.trim()).filter(Boolean);
  for (const line of lines.reverse()) {
    if (!line.startsWith('{')) continue;
    try {
      const result = JSON.parse(line);
      const sessionId = result.session_id || result.sessionId || result.conversation_id || result.conversationId || null;
      const output = provider === 'antigravity' ? result.response : (result.result ?? result.response);
      if (typeof output === 'string') return { output, sessionId };
    } catch {}
  }
  return { output: String(stdout), sessionId: null };
}
const publicRun = run => {
  const { agentSessionId: _secretSessionId, output: _privateOutput, ...visible } = run;
  return { ...visible, output: undefined };
};
const detailedRun = run => ({ ...publicRun(run), output: run.output || '' });


export async function createBridge(config, { baseDir = process.cwd(), env = process.env } = {}) {
  const token = env.FORGELINK_TOKEN;
  if (!token || token.length < 32) throw new Error('FORGELINK_TOKEN must contain at least 32 characters.');
  const pushToken = env.FORGELINK_PUSH_TOKEN || (env.FORGELINK_PUSH_TOKEN_FILE ? (await readFile(env.FORGELINK_PUSH_TOKEN_FILE, 'utf8')).trim() : '');
  const dataDir = path.resolve(baseDir, config.dataDir || './data');
  const pushURL = env.FORGELINK_PUSH_URL || config.pushURL || 'http://127.0.0.1:8788';
  await mkdir(dataDir, { recursive: true, mode: 0o700 });
  const projects = new Map();
  for (const project of config.projects || []) {
    if (!validID(project.id) || projects.has(project.id)) throw new Error('Project IDs must be unique simple identifiers.');
    const cwd = await realpath(path.resolve(baseDir, project.path));
    if (!(await stat(cwd)).isDirectory()) throw new Error(`Not a directory: ${project.id}`);
    const actions = project.actions || [];
    const actionIDs = new Set();
    for (const action of actions) {
      if (!validID(action.id) || actionIDs.has(action.id) || !Array.isArray(action.command) || !action.command.length || action.command.some(a => typeof a !== 'string')) throw new Error(`Invalid action in ${project.id}`);
      actionIDs.add(action.id);
    }
    projects.set(project.id, { ...project, cwd, actions });
  }
  const agents = new Map();
  for (const id of ['claude', 'antigravity', 'deepai']) {
    const item = config.agents?.[id];
    if (!item?.enabled) continue;
    if (id === 'deepai') {
      if (item.mode === 'oracle') {
        let endpoint;
        try { endpoint = new URL(item.endpoint); } catch { throw new Error('Configure the authenticated DeepAI host URL.'); }
        const testLoopback = env.NODE_ENV === 'test' && ['127.0.0.1', 'localhost'].includes(endpoint.hostname);
        if (endpoint.protocol !== 'http:' || !(endpoint.hostname === '172.16.41.1' && endpoint.port === '9395' || testLoopback) || endpoint.username || endpoint.password || endpoint.search || endpoint.hash || endpoint.pathname !== '/') throw new Error('DeepAI Code access is restricted to the existing TrueNAS local Docker host gateway.');
        const oracleSecret = (await readFile(path.resolve(baseDir, item.secretFile || ''), 'utf8')).trim();
        if (oracleSecret.length < 32) throw new Error('The existing DeepAI server credential is missing or invalid.');
        agents.set(id, { name: 'DeepAI Code', kind: 'oracle', endpoint: endpoint.origin, oracleSecret, resumable: true, outputFormat: 'text' });
        continue;
      }
      const endpoint = env[item.webhookURLEnv || 'DEEPAI_WEBHOOK_URL'];
      if (!endpoint) continue;
      const url = new URL(endpoint);
      if (url.protocol !== 'https:' && !(url.protocol === 'http:' && ['127.0.0.1', 'localhost'].includes(url.hostname))) throw new Error('DeepAI webhook requires HTTPS.');
      const signature = item.signature;
      if (signature && (!env[signature.secretEnv] || !['hex', 'base64'].includes(signature.encoding) || !/^[a-zA-Z0-9-]+$/.test(signature.header))) throw new Error('Invalid DeepAI webhook signature configuration.');
      agents.set(id, { ...item, endpoint, name: 'DeepAI Code', kind: 'webhook' });
    } else {
      if (typeof item.executable !== 'string' || !Array.isArray(item.args) || item.args.some(a => typeof a !== 'string') || item.args.filter(a => a === '{prompt}').length !== 1 || item.args.filter(a => a === '{sessionId}').length > 1 || !['text', 'json'].includes(item.outputFormat || 'text')) throw new Error(`Configure ${id} executable, one {prompt}, optional {sessionId}, and a text/json outputFormat.`);
      if (item.resumeArgs && (!Array.isArray(item.resumeArgs) || item.resumeArgs.some(a => typeof a !== 'string') || item.resumeArgs.filter(a => a === '{sessionId}').length !== 1)) throw new Error(`Invalid resumeArgs for ${id}.`);
      if (item.executable.toLowerCase().endsWith('.cmd') || item.executable.toLowerCase().endsWith('.bat')) throw new Error('Use a native executable, or node with a CLI JS entry point; shell wrappers are not accepted.');
      agents.set(id, { ...item, resumable: Boolean(item.resumable || item.resumeArgs), outputFormat: item.outputFormat || 'text', name: id === 'claude' ? 'Claude Code' : 'Antigravity', kind: 'cli' });
    }
  }
  const runs = new Map();
  try {
    for (const run of JSON.parse(await readFile(path.join(dataDir, 'runs.json'), 'utf8'))) {
      if (!validID(run.id)) continue;
      if (!terminal.has(run.status)) Object.assign(run, { status: 'interrupted', endedAt: new Date().toISOString() });
      const previousDeepAIConnectionError = /Cannot reach the authenticated DeepAI Code service|DeepAI Code connection failed/i.test(run.output || '');
      if (run.agentId === 'deepai' && run.status === 'failed' && run.prompt && (!run.output || previousDeepAIConnectionError)) run.responseLost = true;
      runs.set(run.id, run);
    }
  } catch (error) { if (error.code !== 'ENOENT') throw new Error(`Cannot load run history: ${error.message}`); }
  let saving = Promise.resolve();
  const persist = () => {
    const json = JSON.stringify([...runs.values()]);
    const operation = saving.then(async () => {
      const file = path.join(dataDir, 'runs.json');
      await writeFile(`${file}.tmp`, json, { mode: 0o600 });
      await rename(`${file}.tmp`, file);
    });
    saving = operation.catch(error => console.error('Run history write failed:', error.message));
    return operation;
  };
  await persist();
  const active = new Map();
  const childClosures = new Set();
  const stopProcess = child => {
    if (!child.pid) return;
    if (process.platform === 'win32') {
      const killer = spawn('taskkill', ['/pid', String(child.pid), '/T', '/F'], { windowsHide: true, stdio: 'ignore' });
      killer.on('error', () => child.kill());
    } else { try { process.kill(-child.pid, 'SIGKILL'); } catch { child.kill('SIGKILL'); } }
  };
  async function sendApns(run, status) {
    if (pushToken.length < 32) return;
    const notification = { runId: run.id, projectId: run.projectId, title: `ForgeLink · ${run.agentName || run.agentId}`, body: `${status === 'succeeded' ? 'Task complete' : 'Task failed'}: ${run.title}`, status };
    try {
      const response = await fetch(`${pushURL}/notify`, { method: 'POST', headers: { Authorization: `Bearer ${pushToken}`, 'Content-Type': 'application/json' }, body: JSON.stringify(notification), signal: AbortSignal.timeout(10000), redirect: 'error' });
      if (!response.ok) console.warn(`ForgeLink push delivery was not accepted (HTTP ${response.status}).`);
    } catch (error) { console.warn(`ForgeLink push delivery failed (${error.code || 'network error'}).`); }
  }
  async function pushRunNotification(run, status) { await sendApns(run, status); }
  const append = (run, text) => {
    let safe = String(text).replaceAll(token, '[REDACTED]');
    for (const agent of agents.values()) if (agent.oracleSecret) safe = safe.replaceAll(agent.oracleSecret, '[REDACTED]');
    run.output += safe;
    if (run.output.length > MAX_OUTPUT) { run.output = run.output.slice(-MAX_OUTPUT); run.truncated = true; }
    run.revision++;
  };
  async function recoverDeepAI(agent, run, signal, timeoutMs) {
    const endpoint = new URL(`/v1/history/${encodeURIComponent(agent.agentSessionId || run.agentSessionId || run.id)}`, agent.endpoint);
    const deadline = Date.now() + Math.max(1000, timeoutMs);
    let lastError = 'session not yet saved';
    while (!signal.aborted && Date.now() < deadline) {
      try {
        const response = await fetch(endpoint, {
          headers: { 'X-Oracle-Secret': agent.oracleSecret },
          redirect: 'error',
          signal: AbortSignal.any([signal, AbortSignal.timeout(Math.min(10000, Math.max(1000, deadline - Date.now())))])
        });
        if (response.status === 200) {
          const raw = await response.text();
          if (Buffer.byteLength(raw) > MAX_OUTPUT * 2) return { error: 'Stored DeepAI response exceeded the recovery size limit.' };
          const history = JSON.parse(raw);
          const messages = Array.isArray(history.messages) ? history.messages : [];
          const lastUserIndex = messages.map(message => message.role).lastIndexOf('user');
          const lastUser = lastUserIndex >= 0 ? messages[lastUserIndex] : null;
          const lastAssistant = lastUserIndex >= 0 ? messages.slice(lastUserIndex + 1).reverse().find(message => message.role === 'assistant') : null;
          if (lastUser?.text === run.prompt && typeof lastAssistant?.text === 'string' && lastAssistant.text.length) return { reply: lastAssistant.text };
          lastError = 'NAS DeepAI session has no completed matching reply yet';
        } else if (response.status === 404 || response.status === 409 || response.status === 202) {
          await response.body?.cancel();
          lastError = `NAS DeepAI session is still being saved (HTTP ${response.status})`;
        } else {
          await response.body?.cancel();
          return { error: `Could not recover the existing DeepAI session (HTTP ${response.status}). Check DeepAI Code before retrying.` };
        }
      } catch (error) {
        if (signal.aborted) return { error: 'DeepAI recovery was cancelled.' };
        lastError = error.name === 'SyntaxError' ? 'NAS returned an invalid session history' : 'NAS DeepAI session is not available yet';
      }
      await new Promise(resolve => {
        const delay = Math.min(3000, Math.max(0, deadline - Date.now()));
        const timer = setTimeout(resolve, delay);
        signal.addEventListener('abort', () => { clearTimeout(timer); resolve(); }, { once: true });
      });
    }
    return { error: signal.aborted ? 'DeepAI recovery was cancelled.' : `The previous DeepAI turn could not be recovered (${lastError}). Check its existing NAS thread before retrying to avoid duplicate work.` };
  }
  function requestDeepAI(agent, run, signal, timeoutMs) {
    return new Promise((resolve, reject) => {
      const endpoint = new URL('/v1/chat', agent.endpoint);
      const body = JSON.stringify({ message: run.prompt, session_id: agent.agentSessionId || run.agentSessionId || run.id });
      let raw = '';
      let settled = false;
      let responseReceived = false;
      const timeout = setTimeout(() => request.destroy(new Error('DeepAI Code request timed out.')), timeoutMs);
      const cleanup = () => { clearTimeout(timeout); signal.removeEventListener('abort', abort); };
      const finish = (error, value) => {
        if (settled) return;
        settled = true;
        cleanup();
        if (error) reject(error); else resolve(value);
      };
      const abort = () => request.destroy(new Error('DeepAI Code request cancelled.'));
      const request = http.request(endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body), 'X-Oracle-Secret': agent.oracleSecret }
      }, response => {
        responseReceived = true;
        response.setEncoding('utf8');
        if (Number(response.headers['content-length'] || 0) > MAX_OUTPUT) { response.resume(); request.destroy(new Error('DeepAI response exceeded the output limit.')); return; }
        response.on('data', chunk => {
          if (Buffer.byteLength(raw) + Buffer.byteLength(chunk) > MAX_OUTPUT) { request.destroy(new Error('DeepAI response exceeded the output limit.')); return; }
          raw += chunk;
        });
        response.on('end', () => finish(null, { statusCode: response.statusCode || 502, body: raw }));
        response.on('error', error => finish(error));
      });
      request.on('error', error => responseReceived && raw ? finish(null, { statusCode: 502, body: raw }) : finish(error));
      if (signal.aborted) { abort(); return; }
      signal.addEventListener('abort', abort, { once: true });
      request.end(body);
    });
  }
  function execute(run, project, agent, action) {
    let child;
    let childClosed;
    let controller;
    let timer;
    let finished = false;
    let requestedStatus = null;
    const finish = (status, code = null) => {
      if (finished) return;
      finished = true;
      clearTimeout(timer);
      active.delete(run.id);
      Object.assign(run, { status, exitCode: code, endedAt: new Date().toISOString(), revision: run.revision + 1 });
      void persist().catch(() => {});
      if (status === 'succeeded' || status === 'failed') void pushRunNotification(run, status);
    };
    active.set(run.id, { cancel: () => {
      if (requestedStatus || finished) return;
      requestedStatus = 'cancelled';
      append(run, '\n[Cancelled from ForgeLink]\n');
      if (child?.pid) { stopProcess(child); return childClosed; }
      controller?.abort();
      finish('cancelled');
    } });
    const timeoutMs = Math.min(Math.max(config.runTimeoutMs || 1800000, 1000), 7200000);
    timer = setTimeout(() => {
      if (requestedStatus || finished) return;
      requestedStatus = 'failed';
      append(run, '\n[Run timed out]\n');
      if (child?.pid) { stopProcess(child); return; }
      controller?.abort();
      finish('failed');
    }, timeoutMs);
    if (agent?.kind === 'oracle') {
      controller = new AbortController();
      append(run, agent.continuing ? 'Continuing the existing DeepAI session. The complete reply appears when the turn finishes.\n' : 'Connected to DeepAI Code on TrueNAS. The complete reply appears when the turn finishes; partial tokens are not streamed.\n');
      void (async () => {
        try {
          let recoveredReply;
          if (run.responseLost) {
            append(run, '\n[Checking the existing DeepAI session for its response. The task will not be sent again.]\n');
            const recovered = await recoverDeepAI(agent, run, controller.signal, timeoutMs);
            if (!finished && recovered.reply) recoveredReply = recovered.reply;
            else if (!finished) {
              append(run, `${recovered.error || 'Previous DeepAI response is unavailable.'}\n`);
              finish('failed');
              return;
            }
          }
          const response = recoveredReply ? { statusCode: 200, body: JSON.stringify({ ok: true, reply: recoveredReply, session_id: agent.agentSessionId || run.agentSessionId || run.id }) } : await requestDeepAI(agent, run, controller.signal, timeoutMs);
          if (finished) return;
          if (run.responseLost) append(run, '\n[Recovered the completed response from the existing TrueNAS DeepAI session. No duplicate task was sent.]\n');
          if (agent.continuing) append(run, '\n[Continued the existing DeepAI Code session.]\n');
          if (response.statusCode < 200 || response.statusCode >= 300) {
            append(run, `DeepAI Code rejected the task (HTTP ${response.statusCode}). Check the NAS DeepAI session before retrying.\n`);
            finish('failed', response.statusCode);
            return;
          }
          let result;
          try { result = JSON.parse(response.body); } catch { append(run, 'DeepAI Code returned an invalid response. Check the NAS DeepAI session before retrying.\n'); finish('failed'); return; }
          if (result.ok !== true || typeof result.reply !== 'string') { append(run, 'DeepAI Code did not return a completed response. Check the NAS DeepAI session before retrying.\n'); finish('failed'); return; }
          run.agentSessionId = result.session_id || agent.agentSessionId || run.agentSessionId || run.id;
          run.conversationId = agent.conversationId || run.conversationId || run.id;
          run.canContinue = Boolean(agent.resumable);
          append(run, result.reply);
          finish('succeeded', 0);
        } catch (error) {
          if (!finished && !controller.signal.aborted) {
            run.responseLost = true;
            append(run, `DeepAI Code connection failed (${error.code || 'timeout'}). Checking the existing NAS session without resending the task.\n`);
            const recovered = await recoverDeepAI(agent, run, controller.signal, Math.max(timeoutMs - (Date.now() - Date.parse(run.startedAt)), 1000));
            if (!finished && recovered.reply) {
              run.agentSessionId = agent.agentSessionId || run.agentSessionId || run.id;
              run.conversationId = agent.conversationId || run.conversationId || run.id;
              run.canContinue = Boolean(agent.resumable);
              append(run, '\n[Recovered the completed response from the existing TrueNAS DeepAI session. No duplicate task was sent.]\n');
              append(run, recovered.reply);
              finish('succeeded', 0);
              return;
            }
            if (!finished) append(run, `${recovered.error || 'DeepAI reply could not be recovered.'}\n`);
          }
          if (!finished) finish('failed');
        }
      })();
      return;
    }
    if (agent?.kind === 'webhook') {
      controller = new AbortController();
      const webhookTimer = setTimeout(() => controller.abort(), 30000);
      const payload = JSON.stringify({ task: run.prompt, project: project.id, projectName: project.name, runId: run.id });
      const headers = { 'Content-Type': 'application/json' };
      if (agent.signature) {
        const s = agent.signature;
        headers[s.header] = (s.prefix || '') + createHmac('sha256', env[s.secretEnv]).update(payload).digest(s.encoding);
      }
      void fetch(agent.endpoint, { method: 'POST', body: payload, headers, signal: controller.signal, redirect: 'error' })
        .then(async response => {
          await response.body?.cancel();
          if (finished) return;
          if (!response.ok) { append(run, `DeepAI webhook rejected the request (HTTP ${response.status}).\n`); finish('failed'); return; }
          append(run, 'Task accepted by the DeepAI webhook. Open DeepAI Code to review progress and results; this webhook does not stream desktop output.\n');
          finish('dispatched', response.status);
        }).catch(() => { if (!finished) { append(run, 'DeepAI dispatch could not be confirmed. Check DeepAI Code before retrying to avoid duplicate work.\n'); finish('failed'); } })
        .finally(() => clearTimeout(webhookTimer));
      return;
    }
    const childArgs = action?.command ? action.command.slice(1) : buildAgentArguments(agent, run.prompt, agent.agentSessionId || run.agentSessionId || run.id, agent.continuing);
    const command = action?.command || [agent.executable, ...childArgs];
    try {
      // Intentionally no shell, no phone-supplied working directory, and no permission-bypass flags.
      const childEnv = { ...env };
      delete childEnv.FORGELINK_TOKEN;
      delete childEnv.FORGELINK_PUSH_TOKEN;
      delete childEnv.FORGELINK_PUSH_TOKEN_FILE;
      for (const agent of agents.values()) if (agent.oracleSecret) for (const [name, value] of Object.entries(childEnv)) if (value === agent.oracleSecret) delete childEnv[name];
      delete childEnv.DEEPAI_WEBHOOK_URL;
      for (const name of ['APNS_ENABLED', 'APNS_TEAM_ID', 'APNS_KEY_ID', 'APNS_BUNDLE_ID', 'APNS_KEY_FILE', 'APNS_PROFILE_FILE', 'APNS_ENVIRONMENT', 'FORGELINK_APNS_PROFILE']) delete childEnv[name];
      for (const item of agents.values()) if (item.kind === 'webhook') {
        delete childEnv[item.webhookURLEnv || 'DEEPAI_WEBHOOK_URL'];
        if (item.signature) delete childEnv[item.signature.secretEnv];
      }
      child = spawn(command[0], command.slice(1), { cwd: project.cwd, env: childEnv, shell: false, detached: process.platform !== 'win32', windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
      let resolveClosed;
      const closed = new Promise(resolve => { resolveClosed = resolve; });
      childClosed = closed;
      childClosures.add(closed);
      child.once('close', () => { childClosures.delete(closed); resolveClosed(); });
      child.stdout.setEncoding('utf8');
      child.stderr.setEncoding('utf8');
      child.stdout.on('data', text => { if (!finished) append(run, text); });
      child.stderr.on('data', text => { if (!finished) append(run, text); });
      child.once('error', error => { append(run, `Unable to start executable (${error.code || 'spawn error'}). Check the bridge configuration.\n`); finish('failed'); });
      child.once('close', (code, signal) => {
        if (finished) return;
        if (signal) append(run, `\n[Process ended: ${signal}]\n`);
        if (code === 0 && agent?.outputFormat === 'json') {
          const extracted = extractAgentResponse(run.output, agent.outputFormat, agent.id);
          run.output = extracted.output;
          if (extracted.sessionId) run.agentSessionId = extracted.sessionId;
        }
        if (agent?.id === 'antigravity' && code === 0 && !run.agentSessionId) run.agentSessionId = agent.agentSessionId || (agent.continuing ? run.agentSessionId : run.id);
        if (agent?.resumable && code === 0 && !run.agentSessionId) run.agentSessionId = agent.agentSessionId || run.id;
        if (agent?.resumable && code === 0) run.conversationId = agent.conversationId || run.conversationId || run.id;
        run.canContinue = code === 0 && Boolean(agent?.resumable && (run.agentSessionId || run.conversationId));
        finish(requestedStatus || (code === 0 ? 'succeeded' : 'failed'), code);
      });
    } catch { append(run, 'Unable to start run. Check the configured executable.\n'); finish('failed'); }
  }
  const attempts = new Map();
  let closing = false;
  const server = http.createServer(async (req, res) => {
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    const send = (code, body) => { res.writeHead(code); res.end(JSON.stringify(body)); };
    const fail = (status, message) => Object.assign(new Error(message), { status });
    try {
      if (closing) throw fail(503, 'Bridge is shutting down.');
      const ip = req.socket.remoteAddress || 'unknown';
      const now = Date.now();
      for (const [key, value] of attempts) if (value.until < now) attempts.delete(key);
      if ((attempts.get(ip)?.count || 0) >= 20) throw fail(429, 'Too many authentication failures; wait one minute.');
      const supplied = (req.headers.authorization || '').replace(/^Bearer /, '');
      if (!timingSafeEqual(digest(supplied), digest(token))) {
        const value = attempts.get(ip) || { count: 0, until: now + 60000 };
        value.count++; attempts.set(ip, value);
        throw fail(401, 'Pairing token is missing or incorrect.');
      }
      const url = new URL(req.url, 'http://bridge');
      if (req.method === 'GET' && url.pathname === '/v1/status') {
        let pushConfigured = false;
        let apnsEnabled = false;
        if (pushToken.length >= 32) {
          try {
            const result = await fetch(`${pushURL}/health`, { headers: { Authorization: `Bearer ${pushToken}` }, signal: AbortSignal.timeout(1500) });
            if (result.ok) { const health = await result.json(); pushConfigured = true; apnsEnabled = health.apnsEnabled === true; }
          } catch {}
        }
        send(200, { name: config.name || 'ForgeLink Bridge', version: '1.1.0', pushConfigured, apnsEnabled, agents: [...agents].map(([id, a]) => ({ id, name: a.name, kind: a.kind, resumable: Boolean(a.resumable) })), projects: [...projects.values()].map(p => ({ id: p.id, name: p.name, actions: p.actions.map(a => ({ id: a.id, name: a.name })) })) }); return;
      }

      if (req.method === 'PATCH' && url.pathname === '/v1/push/register') {
        const input = await readJsonBody(req, 8192);
        if (typeof input.enabled !== 'boolean' || !validDeviceToken(input.deviceToken) || input.bundleId !== 'com.ross.forgelink') throw fail(400, 'A valid ForgeLink device token, bundle ID, and enabled flag are required.');
        if (pushToken.length < 32) throw fail(503, 'Private push relay is not configured on this bridge.');
        const relayResponse = await fetch(`${pushURL}/register`, { method: 'PATCH', headers: { Authorization: `Bearer ${pushToken}`, 'Content-Type': 'application/json' }, body: JSON.stringify(input), redirect: 'error', signal: AbortSignal.timeout(10000) });
        const result = await relayResponse.json().catch(() => ({}));
        if (!relayResponse.ok) throw fail(502, 'TrueNAS push relay could not register this device.');
        let apnsEnabled = result.apnsEnabled === true;
        try {
          const healthResponse = await fetch(`${pushURL}/health`, { signal: AbortSignal.timeout(1500) });
          if (healthResponse.ok) { const health = await healthResponse.json(); apnsEnabled = health.apnsEnabled === true; }
        } catch {}
        send(200, { enabled: input.enabled, registered: result.registered === true, apnsEnabled, pushConfigured: true });
        return;
      }
      if (req.method === 'GET' && url.pathname === '/v1/runs') {
        send(200, [...runs.values()].reverse().map(publicRun)); return;
      }
      const threadMatch = url.pathname.match(/^\/v1\/threads\/([^/]+)\/runs$/);
      if (threadMatch && req.method === 'GET') {
        let root;
        try { root = decodeURIComponent(threadMatch[1]); } catch { throw fail(400, 'Invalid conversation ID.'); }
        const threadRuns = [...runs.values()].filter(run => threadRootID(runs, run) === root).sort((a, b) => a.startedAt.localeCompare(b.startedAt));
        const messages = threadRuns.flatMap(run => {
          const common = { projectId: run.projectId, projectName: run.projectName, parentRunId: run.parentRunId || null, title: run.title, startedAt: run.startedAt, conversationId: root };
          const userMessage = { ...common, id: `${run.id}_user`, agentId: 'user', prompt: run.prompt || (run.agentId === 'action' ? run.title : ''), status: 'sent', endedAt: null, exitCode: null, output: '', responseLost: false, canContinue: false, revision: 0 };
          const assistantMessage = { ...common, id: `${run.id}_assistant`, agentId: run.agentId === 'action' ? 'system' : run.agentId, prompt: '', status: run.status, endedAt: run.endedAt, exitCode: run.exitCode, output: run.output || '', responseLost: run.responseLost || false, canContinue: run.canContinue || false, revision: run.revision };
          assistantMessage.prompt = assistantMessage.output;
          return [userMessage, assistantMessage];
        });
        send(200, messages);
        return;
      }
      const match = url.pathname.match(/^\/v1\/runs\/([a-zA-Z0-9_-]+)$/);
      if (match) {
        const run = runs.get(match[1]);
        if (!run) throw fail(404, 'Run not found.');
        if (req.method === 'GET') {
          if (run.responseLost && run.status === 'failed' && run.agentId === 'deepai' && !active.has(run.id)) {
            const project = projects.get(run.projectId);
            const agent = agents.get('deepai');
            if (project && agent?.kind === 'oracle') {
              run.status = 'running';
              run.endedAt = null;
              run.revision++;
              await persist();
              execute(run, project, { ...agent, conversationId: threadRootID(runs, run), agentSessionId: run.agentSessionId || run.id, continuing: true }, null);
            }
          }
          send(200, detailedRun(run));
          return;
        }
        if (req.method === 'DELETE') { await active.get(run.id)?.cancel(); send(200, detailedRun(run)); return; }
      }
      if (req.method === 'POST' && url.pathname === '/v1/runs') {
        if (!req.headers['content-type']?.startsWith('application/json')) throw fail(415, 'Use application/json.');
        let input;
        try { input = await readJsonBody(req, 65536); } catch (error) { throw fail(error.status || 400, error.status ? error.message : 'Invalid JSON.'); }
        if (!input || typeof input !== 'object') throw fail(400, 'Expected a JSON object.');
        const project = projects.get(input.projectId);
        if (!project) throw fail(400, 'Choose a configured project.');
        if ([...active.keys()].some(id => runs.get(id).projectId === project.id)) throw fail(409, 'This project already has an active run.');
        if (active.size >= 4) throw fail(429, 'Four runs are already active.');
        const agent = agents.get(input.agentId);
        const action = project.actions.find(a => a.id === input.actionId);
        if (input.actionId ? !action : !agent) throw fail(400, 'Choose an enabled agent or saved action.');
        if (!input.actionId && (typeof input.prompt !== 'string' || !input.prompt.trim() || input.prompt.length > 16000 || input.prompt.includes('\0'))) throw fail(400, 'Task must contain 1–16000 characters and no null bytes.');
        const parent = input.parentRunId == null ? null : runs.get(input.parentRunId);
        if (input.parentRunId != null && (!parent || parent.projectId !== project.id || parent.agentId !== input.agentId || input.actionId || parent.status !== 'succeeded' || parent.canContinue !== true || !agent?.resumable)) throw fail(400, 'This conversation cannot be continued. Choose a supported completed agent run.');
        const id = randomUUID();
        const conversationId = parent ? threadRootID(runs, parent) : id;
        const agentSessionId = parent ? (parent.agentSessionId || parent.id) : id;
        const run = { id, projectId: project.id, projectName: project.name, agentId: input.actionId ? 'action' : input.agentId, title: action?.name || (parent ? `↳ ${input.prompt.trim().slice(0, 94)}` : input.prompt.trim().slice(0, 100)), prompt: input.actionId ? '' : input.prompt.trim(), status: 'running', startedAt: new Date().toISOString(), endedAt: null, exitCode: null, output: '', revision: 0, truncated: false, parentRunId: parent?.id || null, conversationId, agentSessionId, canContinue: false };
        // Reserve the project before asynchronous persistence to prevent concurrent submissions.
        active.set(run.id, { cancel: () => {} });
        runs.set(run.id, run);
        while (runs.size > MAX_RUNS) {
          const oldest = [...runs.values()].find(r => terminal.has(r.status));
          if (!oldest) break;
          runs.delete(oldest.id);
        }
        try { await persist(); } catch { active.delete(run.id); runs.delete(run.id); throw fail(500, 'Cannot save run; no command was started.'); }
        execute(run, project, input.actionId ? null : { ...agent, conversationId, agentSessionId, continuing: Boolean(parent) }, action);
        send(201, publicRun(run)); return;
      }
      throw fail(404, 'Endpoint not found.');
    } catch (error) { if (!res.headersSent) send(error.status || 500, { error: error.status ? error.message : 'Bridge error. See server logs.' }); }
  });
  server.requestTimeout = 15000;
  server.headersTimeout = 10000;
  const checkpoint = setInterval(() => { if (active.size) void persist().catch(() => {}); }, 3000);
  checkpoint.unref();
  return {
    server,
    async close() {
      closing = true;
      clearInterval(checkpoint);
      for (const item of active.values()) item.cancel();
      await Promise.all([...childClosures]);
      await persist();
      if (server.listening) await new Promise(resolve => server.close(resolve));
      await saving;
    }
  };
}
