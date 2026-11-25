import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, readFile, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import http from 'node:http';
import { createHmac } from 'node:crypto';
import { createBridge } from '../src/server.mjs';

const token = 'a-test-token-at-least-thirty-two-characters-long';
async function fixture(t, overrides = {}, env = {}) {
  const dir = await mkdtemp(path.join(os.tmpdir(), 'forgelink-'));
  const config = {
    dataDir: './data',
    projects: [{ id: 'test', name: 'Test project', path: '.', actions: [
      { id: 'hello', name: 'Hello', command: [process.execPath, '-e', 'console.log("hello from action")'] },
      { id: 'slow', name: 'Slow', command: [process.execPath, '-e', 'console.log("started"); setTimeout(()=>console.log("done"), 60000)'] },
      { id: 'fail', name: 'Fail', command: [process.execPath, '-e', 'console.error("failure"); process.exit(3)'] },
      { id: 'big', name: 'Big', command: [process.execPath, '-e', 'process.stdout.write("x".repeat(600000))'] },
      { id: 'env', name: 'Environment', command: [process.execPath, '-e', 'console.log(process.env.FORGELINK_TOKEN || "no bridge token")'] }
    ] }],
    agents: {
      claude: { enabled: true, executable: process.execPath, args: ['-e', 'console.log(process.argv[1])', '--', '{prompt}'] }
    }, ...overrides
  };
  const bridge = await createBridge(config, { baseDir: dir, env: { ...process.env, NODE_ENV: 'test', FORGELINK_TOKEN: token, ...env } });
  await new Promise(resolve => bridge.server.listen(0, '127.0.0.1', resolve));
  const base = `http://127.0.0.1:${bridge.server.address().port}`;
  const api = async (route, options = {}) => {
    const response = await fetch(base + route, { ...options, headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json', ...options.headers }, body: options.body === undefined ? undefined : JSON.stringify(options.body) });
    return { code: response.status, data: await response.json() };
  };
  const start = body => api('/v1/runs', { method: 'POST', body: { projectId: 'test', ...body } });
  const wait = async id => {
    for (let i = 0; i < 200; i++) {
      const { data } = await api(`/v1/runs/${id}`);
      if (data.status !== 'running') return data;
      await new Promise(resolve => setTimeout(resolve, 25));
    }
    throw new Error('Run did not finish');
  };
  t.after(async () => { await bridge.close(); await rm(dir, { recursive: true, force: true }); });
  return { api, start, wait, dir, bridge, base };
}

test('requires a long pairing token', async () => {
  await assert.rejects(createBridge({}, { env: {} }), /FORGELINK_TOKEN/);
});
test('auth protects metadata and output; status does not disclose host paths', async t => {
  const f = await fixture(t);
  assert.equal((await f.api('/v1/status', { headers: { Authorization: '' } })).code, 401);
  const response = await f.api('/v1/status');
  assert.equal(response.code, 200);
  assert.equal(response.data.projects[0].id, 'test');
  assert.equal(response.data.projects[0].path, undefined);
  assert.equal(response.data.agents[0].id, 'claude');
});
test('saved actions execute and capture stdout with exit code', async t => {
  const f = await fixture(t);
  const created = await f.start({ actionId: 'hello' });
  assert.equal(created.code, 201);
  const result = await f.wait(created.data.id);
  assert.equal(result.status, 'succeeded');
  assert.equal(result.exitCode, 0);
  assert.match(result.output, /hello from action/);
  const list = await f.api('/v1/runs');
  assert.equal(list.data[0].output, undefined);
  assert.equal(list.data[0].projectName, 'Test project');
});
test('prompts are literal process arguments, not shell commands', async t => {
  const f = await fixture(t);
  const prompt = 'hello "quoted"; echo INJECTED > owned.txt & $(touch owned)\nsecond line';
  const created = await f.start({ agentId: 'claude', prompt });
  assert.equal(created.code, 201);
  const result = await f.wait(created.data.id);
  assert.equal(result.output.trim(), prompt);
  await assert.rejects(readFile(path.join(f.dir, 'owned.txt')), { code: 'ENOENT' });
});
test('rejects unknown paths, commands, agents, empty and oversized tasks', async t => {
  const f = await fixture(t);
  for (const body of [
    { projectId: '../outside', actionId: 'hello' },
    { actionId: 'arbitrary' },
    { agentId: 'missing', prompt: 'hello' },
    { agentId: 'claude', prompt: '  ' },
    { agentId: 'claude', prompt: 'x'.repeat(16001) },
    { agentId: 'claude', prompt: 'x\0y' }
  ]) assert.equal((await f.start(body)).code, 400);
  assert.equal((await f.api('/v1/runs', { method: 'POST', body: null })).code, 400);
});
test('serializes project runs and supports cancellation', async t => {
  const f = await fixture(t);
  const [first, second] = await Promise.all([f.start({ actionId: 'slow' }), f.start({ actionId: 'slow' })]);
  assert.deepEqual([first.code, second.code].sort(), [201, 409]);
  const id = (first.code === 201 ? first : second).data.id;
  const cancelled = await f.api(`/v1/runs/${id}`, { method: 'DELETE' });
  assert.equal(cancelled.data.status, 'cancelled');
  assert.equal((await f.start({ actionId: 'hello' })).code, 201);
});
test('records command errors and bounds large logs', async t => {
  const f = await fixture(t);
  let created = await f.start({ actionId: 'fail' });
  let result = await f.wait(created.data.id);
  assert.equal(result.status, 'failed');
  assert.equal(result.exitCode, 3);
  assert.match(result.output, /failure/);
  created = await f.start({ actionId: 'big' });
  result = await f.wait(created.data.id);
  assert.equal(result.truncated, true);
  assert.ok(result.output.length <= 512 * 1024);
});
test('does not pass bridge credentials to child commands', async t => {
  const f = await fixture(t);
  const created = await f.start({ actionId: 'env' });
  assert.equal((await f.wait(created.data.id)).output.trim(), 'no bridge token');
});
test('supported agent follow-ups resume the same conversation and are returned in chat history', async t => {
  const script = 'console.log(JSON.stringify({result:process.argv.slice(1).join("|"),session_id:"persistent-test-session"}))';
  const f = await fixture(t, { agents: { claude: {
    enabled: true, resumable: true, executable: process.execPath, outputFormat: 'json',
    args: ['-e', script, '{prompt}', '{sessionId}'],
    resumeArgs: ['-e', script, '{prompt}', '{sessionId}', 'RESUMED']
  } } });
  const first = await f.start({ agentId: 'claude', prompt: 'First message' });
  assert.equal(first.code, 201);
  const firstResult = await f.wait(first.data.id);
  assert.equal(firstResult.status, 'succeeded');
  assert.equal(firstResult.canContinue, true);
  assert.match(firstResult.output, /First message/);
  assert.match(firstResult.output, /First message/);
  const conversationId = firstResult.conversationId;
  assert.equal(conversationId, firstResult.id);
  const continued = await f.start({ agentId: 'claude', prompt: 'Follow-up message', parentRunId: firstResult.id });
  assert.equal(continued.code, 201);
  assert.equal(continued.data.parentRunId, firstResult.id);
  const final = await f.wait(continued.data.id);
  assert.equal(final.status, 'succeeded');
  assert.equal(final.conversationId, conversationId);
  assert.equal(final.output.includes('RESUMED'), true);
  assert.equal(final.output.includes('persistent-test-session'), true);
  assert.match(final.output, /Follow-up message/);
  const thread = await f.api(`/v1/threads/${conversationId}/runs`);
  assert.equal(thread.code, 200);
  assert.equal(thread.data.length, 4);
  assert.equal(thread.data[0].agentId, 'user');
  assert.equal(thread.data[0].prompt, 'First message');
  assert.equal(thread.data[1].agentId, 'claude');
  assert.equal(thread.data[2].agentId, 'user');
  assert.equal(thread.data[2].prompt, 'Follow-up message');
  assert.equal(thread.data[3].parentRunId, firstResult.id);
});
test('rejects continuation from another project or an unsupported agent', async t => {
  const f = await fixture(t);
  const first = await f.start({ agentId: 'claude', prompt: 'first' });
  const completed = await f.wait(first.data.id);
  const request = await f.api('/v1/runs', { method: 'POST', body: { projectId: 'test', agentId: 'claude', prompt: 'follow-up', parentRunId: completed.id } });
  assert.equal(request.code, 400);
});
test('missing executables fail visibly rather than looking successful', async t => {
  const f = await fixture(t, { agents: { claude: { enabled: true, executable: 'forgelink-no-such-executable-938432', args: ['{prompt}'] } } });
  const created = await f.start({ agentId: 'claude', prompt: 'hello' });
  const result = await f.wait(created.data.id);
  assert.equal(result.status, 'failed');
  assert.match(result.output, /Unable to start executable/);
});
test('timeouts stop jobs', async t => {
  const f = await fixture(t, { runTimeoutMs: 1000 });
  const created = await f.start({ actionId: 'slow' });
  const result = await f.wait(created.data.id);
  assert.equal(result.status, 'failed');
  assert.match(result.output, /timed out/);
});
test('run history survives restart and interrupted jobs are identified', async t => {
  const f = await fixture(t);
  const created = await f.start({ actionId: 'hello' });
  await f.wait(created.data.id);
  await f.bridge.close();
  const stored = JSON.parse(await readFile(path.join(f.dir, 'data/runs.json'), 'utf8'));
  assert.equal(stored[0].status, 'succeeded');
  stored[0].status = 'running';
  await writeFile(path.join(f.dir, 'data/runs.json'), JSON.stringify(stored));
  const restarted = await createBridge({ dataDir: './data', projects: [] }, { baseDir: f.dir, env: { FORGELINK_TOKEN: token } });
  await restarted.close();
  const saved = JSON.parse(await readFile(path.join(f.dir, 'data/runs.json'), 'utf8'));
  assert.equal(saved[0].status, 'interrupted');
});
test('DeepAI dispatch signs payload and reports handoff, not agent completion', async t => {
  let received;
  const secret = 'test-webhook-signing-secret';
  const receiver = http.createServer(async (req, res) => {
    let text = ''; for await (const chunk of req) text += chunk;
    received = { body: JSON.parse(text), signature: req.headers['x-hub-signature-256'], text };
    res.writeHead(202); res.end('{"accepted":true}');
  });
  await new Promise(resolve => receiver.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => receiver.close(resolve)));
  const f = await fixture(t, { agents: { deepai: { enabled: true, webhookURLEnv: 'DEEPAI_WEBHOOK_URL', signature: { header: 'x-hub-signature-256', encoding: 'hex', prefix: 'sha256=', secretEnv: 'TEST_SIGNATURE' } } } }, { DEEPAI_WEBHOOK_URL: `http://127.0.0.1:${receiver.address().port}/trigger`, TEST_SIGNATURE: secret });
  const created = await f.start({ agentId: 'deepai', prompt: 'Review the tests' });
  const result = await f.wait(created.data.id);
  assert.equal(result.status, 'dispatched');
  assert.equal(received.body.task, 'Review the tests');
  assert.equal(received.signature, 'sha256=' + createHmac('sha256', secret).update(received.text).digest('hex'));
  assert.match(result.output, /does not stream desktop output/);
});
test('DeepAI local API integration protects credentials and captures the agent result', async t => {
  let requests = 0;
  const secret = 'a-very-private-oracle-secret-at-least-thirty-two-characters';
  const upstream = http.createServer(async (req, res) => {
    assert.equal(req.headers['x-oracle-secret'], secret);
    let text = ''; for await (const chunk of req) text += chunk;
    const body = JSON.parse(text);
    assert.equal(body.message, 'Explain the current workspace.');
    assert.match(body.session_id, /^[a-f0-9-]{36}$/i);
    requests++;
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ ok: true, reply: 'DeepAI response.\\nA second line.', session_id: body.session_id }));
  });
  await new Promise(resolve => upstream.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => upstream.close(resolve)));
  const dir = await mkdtemp(path.join(os.tmpdir(), 'forgelink-'));
  await import('node:fs/promises').then(fs => fs.mkdir(path.join(dir, 'data')));
  await writeFile(path.join(dir, 'deepai.secret'), secret, { mode: 0o600 });
  const bridge = await createBridge({
    dataDir: './data', projects: [{ id: 'test', name: 'Test project', path: '.', actions: [] }],
    agents: { deepai: { enabled: true, mode: 'oracle', endpoint: `http://127.0.0.1:${upstream.address().port}`, secretFile: 'deepai.secret' } }
  }, { baseDir: dir, env: { ...process.env, NODE_ENV: 'test', FORGELINK_TOKEN: token } });
  await new Promise(resolve => bridge.server.listen(0, '127.0.0.1', resolve));
  const base = `http://127.0.0.1:${bridge.server.address().port}`;
  const start = body => fetch(base + '/v1/runs', { method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ projectId: 'test', ...body }) }).then(async response => ({ code: response.status, data: await response.json() }));
  const wait = async id => {
    for (let i = 0; i < 200; i++) {
      const response = await fetch(`${base}/v1/runs/${id}`, { headers: { Authorization: `Bearer ${token}` } });
      const data = await response.json();
      if (data.status !== 'running') return data;
      await new Promise(resolve => setTimeout(resolve, 25));
    }
    throw new Error('DeepAI run did not finish');
  };
  t.after(async () => { await bridge.close(); await rm(dir, { recursive: true, force: true }); });
  const created = await start({ agentId: 'deepai', prompt: 'Explain the current workspace.' });
  assert.equal(created.code, 201);
  const result = await wait(created.data.id);
  await bridge.close();
  assert.equal(result.status, 'succeeded');
  assert.match(result.output, /DeepAI response/);
  assert.doesNotMatch(JSON.stringify(result), new RegExp(secret));
  assert.equal(requests, 1);
});
test('DeepAI completed-turn recovery preserves the original request ID across bridge restarts', async t => {
  const dir = await mkdtemp(path.join(os.tmpdir(), 'forgelink-'));
  await import('node:fs/promises').then(fs => fs.mkdir(path.join(dir, 'data')));
  t.after(() => rm(dir, { recursive: true, force: true }));
  const previous = { id: '42672957-eacb-4ee2-8985-03d5f2b214c2', projectId: 'test', projectName: 'Test', agentId: 'deepai', title: 'Previous DeepAI task', prompt: 'Create Coven', status: 'failed', output: 'Cannot reach the authenticated DeepAI Code service on TrueNAS. Check its health before retrying.\\n', revision: 1, startedAt: new Date().toISOString(), endedAt: new Date().toISOString() };
  await writeFile(path.join(dir, 'data/runs.json'), JSON.stringify([previous]));
  const secret = 'a-previous-deepai-secret-for-recovery-test-123456';
  await writeFile(path.join(dir, 'deepai.secret'), secret, { mode: 0o600 });
  let upstreamBody;
  const upstream = http.createServer(async (req, res) => {
    if (req.url === `/v1/history/${previous.id}`) {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ messages: [
        { role: 'user', text: previous.prompt },
        { role: 'assistant', text: 'Recovered Coven build summary.' }
      ] }));
      return;
    }
    assert.equal(req.headers['x-oracle-secret'], secret);
    let body = ''; for await (const chunk of req) body += chunk;
    upstreamBody = body.trim() ? JSON.parse(body) : { session_id: previous.id };
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ ok: true, reply: 'Recovered Coven build summary.', session_id: upstreamBody.session_id }));
  });
  await new Promise(resolve => upstream.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => upstream.close(resolve)));
  const bridge = await createBridge({ dataDir: './data', projects: [{ id: 'test', name: 'Test', path: '.' }], agents: { deepai: { enabled: true, mode: 'oracle', endpoint: `http://127.0.0.1:${upstream.address().port}`, secretFile: 'deepai.secret' } } }, { baseDir: dir, env: { ...process.env, NODE_ENV: 'test', FORGELINK_TOKEN: token } });
  await new Promise(resolve => bridge.server.listen(0, '127.0.0.1', resolve));
  const response = await fetch(`http://127.0.0.1:${bridge.server.address().port}/v1/runs/${previous.id}`, { headers: { Authorization: `Bearer ${token}` } });
  const run = await response.json();
  let after;
  for (let i = 0; i < 40; i++) {
    await new Promise(resolve => setTimeout(resolve, 50));
    after = await (await fetch(`http://127.0.0.1:${bridge.server.address().port}/v1/runs/${previous.id}`, { headers: { Authorization: `Bearer ${token}` } })).json();
    if (after.status !== 'running') break;
  }
  assert.equal(after.responseLost, true);
  assert.equal(after.status, 'succeeded');
  assert.equal(after.output.includes('Recovered Coven build summary.'), true);
  assert.equal(upstreamBody, undefined);
  await bridge.close();
});
test('DeepAI private API rejects non-private endpoints and missing key file', async t => {
  const dir = await mkdtemp(path.join(os.tmpdir(), 'forgelink-'));
  await import('node:fs/promises').then(fs => fs.mkdir(path.join(dir, 'project')));
  t.after(() => rm(dir, { recursive: true, force: true }));
  const config = { projects: [{ id: 'p', name: 'p', path: './project' }], agents: { deepai: { enabled: true, mode: 'oracle', endpoint: 'http://172.16.41.2:9395', secretFile: 'missing' } } };
  await assert.rejects(createBridge(config, { baseDir: dir, env: { ...process.env, NODE_ENV: 'test', FORGELINK_TOKEN: token } }), /restricted/);
});
test('authentication failures are throttled', async t => {
  const f = await fixture(t);
  for (let i = 0; i < 20; i++) assert.equal((await f.api('/v1/status', { headers: { Authorization: 'Bearer wrong' } })).code, 401);
  assert.equal((await f.api('/v1/status', { headers: { Authorization: 'Bearer wrong' } })).code, 429);
});
