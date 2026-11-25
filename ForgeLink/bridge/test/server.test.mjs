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
  const bridge = await createBridge(config, { baseDir: dir, env: { ...process.env, FORGELINK_TOKEN: token, ...env } });
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
test('authentication failures are throttled', async t => {
  const f = await fixture(t);
  for (let i = 0; i < 20; i++) assert.equal((await f.api('/v1/status', { headers: { Authorization: 'Bearer wrong' } })).code, 401);
  assert.equal((await f.api('/v1/status', { headers: { Authorization: 'Bearer wrong' } })).code, 429);
});
