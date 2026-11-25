import { randomBytes } from 'node:crypto';
import { readFile, writeFile, access, chmod } from 'node:fs/promises';
import path from 'node:path';
import { createBridge } from './server.mjs';

const configPath = path.resolve(process.env.FORGELINK_CONFIG || 'config.json');
if (process.argv[2] === 'init') {
  for (const file of [configPath, '.env']) {
    try { await access(file); throw new Error(`${file} already exists; refusing to overwrite.`); }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
  }
  const templateName = process.env.FORGELINK_TEMPLATE === 'truenas' ? 'config.truenas.example.json' : 'config.example.json';
  const template = JSON.parse(await readFile(new URL(`../${templateName}`, import.meta.url), 'utf8'));
  await writeFile(configPath, JSON.stringify(template, null, 2) + '\n', { flag: 'wx', mode: 0o600 });
  await writeFile('.env', `FORGELINK_TOKEN=${randomBytes(32).toString('hex')}\n`, { flag: 'wx', mode: 0o600 });
  await chmod('.env', 0o600);
  console.log('Created config.json and .env. Configure project paths and agent executables, then run npm start. The pairing token is in .env; enter it in the iPhone app, not chat.');
} else {
  try { process.loadEnvFile('.env'); } catch (error) { if (error.code !== 'ENOENT') throw error; }
  const config = JSON.parse(await readFile(configPath, 'utf8'));
  const bridge = await createBridge(config, { baseDir: path.dirname(configPath) });
  const port = Number(process.env.PORT || config.port || 8787);
  const host = process.env.HOST || config.host || '127.0.0.1';
  bridge.server.on('error', error => { console.error(`Bridge listener failed: ${error.message}`); process.exitCode = 1; });
  bridge.server.listen(port, host, () => console.log(`ForgeLink Bridge listening on ${host}:${port}. Use HTTPS or a private VPN to connect; do not expose this HTTP listener publicly.`));
  let stopping = false;
  for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, async () => {
    if (stopping) return;
    stopping = true;
    await bridge.close();
  });
}
