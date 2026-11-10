import { describe, expect, test } from 'bun:test';
import { address, hostname, makeTab, gothicScript, restoreSettings, websiteThemeEnabled, siteHost } from '../packages/mobile/lib/browser';
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
    expect(gothicScript(true)).toContain('engine.enable');
    expect(gothicScript(false)).toContain('old.remove()');
    expect(gothicScript(false)).toContain('engine.disable()');
    expect(gothicScript(false)).not.toContain("createElement('style')");
  });
  test('old settings safely migrate and malformed site lists are filtered', () => {
    expect(restoreSettings({ gothic: true, search: 'google' })).toEqual({ gothic: true, search: 'google', originalSites: [] });
    expect(restoreSettings({ originalSites: ['WWW.Google.COM', 'www.google.com', 'bad host', null as unknown as string] }).originalSites).toEqual(['www.google.com']);
    expect(restoreSettings().gothic).toBe(false);
  });
  test('site exceptions apply to the exact hostname, including redirected URLs', () => {
    const settings = restoreSettings({ gothic: true, originalSites: ['www.google.com'] });
    expect(siteHost('https://www.google.com/search?q=test')).toBe('www.google.com');
    expect(websiteThemeEnabled(settings, 'https://www.google.com/')).toBe(false);
    expect(websiteThemeEnabled(settings, 'https://en.wikipedia.org/')).toBe(true);
    expect(websiteThemeEnabled({ ...settings, gothic: false }, 'https://en.wikipedia.org/')).toBe(false);
    expect(gothicScript(true, settings.originalSites)).toContain('location.hostname.toLowerCase()');
  });
});