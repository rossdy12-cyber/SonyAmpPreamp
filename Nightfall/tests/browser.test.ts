import { describe, expect, test } from 'bun:test';
import { address, hostname, makeTab, gothicScript } from '../packages/mobile/lib/browser';
describe('Nightfall browser helpers', () => {
  test('iOS and Android identifiers pass the installed Expo validators', () => {
    const result = Bun.spawnSync(['node', new URL('../ci/validate-config.cjs', import.meta.url).pathname]);
    expect(result.exitCode).toBe(0);
  });
  test('supports HTTPS and HTTP addresses without forcing external navigation', () => {
    expect(address('https://runable.com/path', 'duckduckgo')).toBe('https://runable.com/path');
    expect(address('http://example.com', 'google')).toBe('http://example.com');
    expect(address('example.com/path', 'google')).toBe('https://example.com/path');
  });
  test('search encodes input and does not execute URL schemes', () => {
    expect(address('gothic architecture', 'duckduckgo')).toBe('https://duckduckgo.com/?q=gothic%20architecture');
    expect(address('javascript:alert(1)', 'google')).toBe('https://www.google.com/search?q=javascript%3Aalert(1)');
    expect(address('', 'google')).toBe('');
  });
  test('new private tabs carry their privacy flag', () => {
    expect(makeTab(true).private).toBe(true);
    expect(makeTab(false).url).toBe('');
    expect(makeTab().id).not.toBe(makeTab().id);
    expect(hostname('https://www.example.com/a')).toBe('example.com');
  });
  test('gothic theme removal is reversible and disable does not add a stylesheet', () => {
    expect(gothicScript(true)).toContain("createElement('style')");
    expect(gothicScript(false)).toContain('s.remove()');
    expect(gothicScript(false)).not.toContain("createElement('style')");
  });
});