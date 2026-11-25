import http from 'node:http';
import { createHash, randomUUID, timingSafeEqual, createHmac } from 'node:crypto';
import { spawn } from 'node:child_process';
import { readFile, writeFile, mkdir, rename, realpath, stat } from 'node:fs/promises';
import path from 'node:path';

const MAX_OUTPUT = 512 * 1024;
const MAX_RUNS = 100;
const terminal = new Set(['succeeded', 'failed', 'cancelled', 'interrupted', 'dispatched']);
const digest = value => createHash('sha256').update(value).digest();
const validID = value => typeof value === 'string' && /^[a-zA-Z0-9_-]{1,80}$/.test(value);
const publicRun = run => ({ ...run, output: undefined });

export async function createBridge(config, { baseDir = process.cwd(), env = process.env } = {}) {
  const token = env.FORGELINK_TOKEN;
  if (!token || token.length < 32) throw new Error('FORGELINK_TOKEN must contain at least 32 characters.');
  const dataDir = path.resolve(baseDir, config.dataDir || './data');
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
      const endpoint = env[item.webhookURLEnv || 'DEEPAI_WEBHOOK_URL'];
      if (!endpoint) continue;
      const url = new URL(endpoint);
      if (url.protocol !== 'https:' && !(url.protocol === 'http:' && ['127.0.0.1', 'localhost'].includes(url.hostname))) throw new Error('DeepAI webhook requires HTTPS.');
      const signature = item.signature;
      if (signature && (!env[signature.secretEnv] || !['hex', 'base64'].includes(signature.encoding) || !/^[a-zA-Z0-9-]+$/.test(signature.header))) throw new Error('Invalid DeepAI webhook signature configuration.');
      agents.set(id, { ...item, endpoint, name: 'DeepAI Code', kind: 'webhook' });
    } else {
      if (typeof item.executable !== 'string' || !Array.isArray(item.args) || item.args.some(a => typeof a !== 'string') || item.args.filter(a => a === '{prompt}').length !== 1) throw new Error(`Configure ${id} executable and exactly one {prompt} argument.`);
      if (item.executable.toLowerCase().endsWith('.cmd') || item.executable.toLowerCase().endsWith('.bat')) throw new Error('Use a native executable, or node with a CLI JS entry point; shell wrappers are not accepted.');
      agents.set(id, { ...item, name: id === 'claude' ? 'Claude Code' : 'Antigravity', kind: 'cli' });
    }
  }
  const runs = new Map();
  try {
    for (const run of JSON.parse(await readFile(path.join(dataDir, 'runs.json'), 'utf8'))) {
      if (!validID(run.id)) continue;
      if (!terminal.has(run.status)) Object.assign(run, { status: 'interrupted', endedAt: new Date().toISOString() });
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
  const append = (run, text) => {
    run.output += text.replaceAll(token, '[REDACTED]');
    if (run.output.length > MAX_OUTPUT) { run.output = run.output.slice(-MAX_OUTPUT); run.truncated = true; }
    run.revision++;
  };
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
    const command = action?.command || [agent.executable, ...agent.args.map(arg => arg === '{prompt}' ? run.prompt : arg)];
    try {
      // Intentionally no shell, no phone-supplied working directory, and no permission-bypass flags.
      const childEnv = { ...env };
      delete childEnv.FORGELINK_TOKEN;
      delete childEnv.DEEPAI_WEBHOOK_URL;
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
        send(200, { name: config.name || 'ForgeLink Bridge', version: '1.0.0', agents: [...agents].map(([id, a]) => ({ id, name: a.name, kind: a.kind })), projects: [...projects.values()].map(p => ({ id: p.id, name: p.name, actions: p.actions.map(a => ({ id: a.id, name: a.name })) })) }); return;
      }
      if (req.method === 'GET' && url.pathname === '/v1/runs') {
        send(200, [...runs.values()].reverse().map(publicRun)); return;
      }
      const match = url.pathname.match(/^\/v1\/runs\/([a-zA-Z0-9_-]+)$/);
      if (match) {
        const run = runs.get(match[1]);
        if (!run) throw fail(404, 'Run not found.');
        if (req.method === 'GET') { send(200, run); return; }
        if (req.method === 'DELETE') { await active.get(run.id)?.cancel(); send(200, run); return; }
      }
      if (req.method === 'POST' && url.pathname === '/v1/runs') {
        if (!req.headers['content-type']?.startsWith('application/json')) throw fail(415, 'Use application/json.');
        let body = '';
        for await (const chunk of req) {
          body += chunk.toString();
          if (Buffer.byteLength(body) > 65536) throw fail(413, 'Request is too large.');
        }
        let input;
        try { input = JSON.parse(body); } catch { throw fail(400, 'Invalid JSON.'); }
        if (!input || typeof input !== 'object') throw fail(400, 'Expected a JSON object.');
        const project = projects.get(input.projectId);
        if (!project) throw fail(400, 'Choose a configured project.');
        if ([...active.keys()].some(id => runs.get(id).projectId === project.id)) throw fail(409, 'This project already has an active run.');
        if (active.size >= 4) throw fail(429, 'Four runs are already active.');
        const agent = agents.get(input.agentId);
        const action = project.actions.find(a => a.id === input.actionId);
        if (input.actionId ? !action : !agent) throw fail(400, 'Choose an enabled agent or saved action.');
        if (!input.actionId && (typeof input.prompt !== 'string' || !input.prompt.trim() || input.prompt.length > 16000 || input.prompt.includes('\0'))) throw fail(400, 'Task must contain 1–16000 characters and no null bytes.');
        const run = { id: randomUUID(), projectId: project.id, projectName: project.name, agentId: input.actionId ? 'action' : input.agentId, title: action?.name || input.prompt.trim().slice(0, 100), prompt: input.actionId ? '' : input.prompt.trim(), status: 'running', startedAt: new Date().toISOString(), endedAt: null, exitCode: null, output: '', revision: 0, truncated: false };
        // Reserve the project before asynchronous persistence to prevent concurrent submissions.
        active.set(run.id, { cancel: () => {} });
        runs.set(run.id, run);
        while (runs.size > MAX_RUNS) {
          const oldest = [...runs.values()].find(r => terminal.has(r.status));
          if (!oldest) break;
          runs.delete(oldest.id);
        }
        try { await persist(); } catch { active.delete(run.id); runs.delete(run.id); throw fail(500, 'Cannot save run; no command was started.'); }
        execute(run, project, input.actionId ? null : agent, action);
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
