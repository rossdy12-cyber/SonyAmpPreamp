import { themeEngineSource } from './theme-engine-source';

export type Tab = { id: string; url: string; lastUrl?: string; title: string; private: boolean };
export type SavedPage = { id: string; url: string; title: string; date: number };
export type Download = { id: string; name: string; uri: string; date: number };
export type BrowserSettings = { gothic: boolean; search: 'duckduckgo' | 'google'; originalSites: string[] };
export function siteHost(url: string) { try { return new URL(url).hostname.toLowerCase(); } catch { return ''; } }
export function restoreSettings(value: Partial<BrowserSettings> = {}): BrowserSettings {
  return { gothic: !!value.gothic, search: value.search === 'google' ? 'google' : 'duckduckgo', originalSites: Array.isArray(value.originalSites) ? [...new Set(value.originalSites.filter((host): host is string => typeof host === 'string' && /^[a-z0-9.-]+$/i.test(host)).map(host => host.toLowerCase()))] : [] };
}
export function websiteThemeEnabled(settings: BrowserSettings, url: string) { return settings.gothic && !settings.originalSites.includes(siteHost(url)); }
export const palette = { bg: '#0C0D0E', panel: '#151617', raised: '#1D1E20', gold: '#C3A16A', text: '#EEE8DC', muted: '#96938E', border: '#30302E', wine: '#442531' };
export const makeId = () => `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
export const makeTab = (isPrivate = false, url = ''): Tab => ({ id: makeId(), url, title: url ? hostname(url) : 'New sanctuary', private: isPrivate });
export function hostname(url: string) { try { return new URL(url).hostname.replace(/^www\./, ''); } catch { return url; } }
export function address(value: string, search: BrowserSettings['search']) {
  const input = value.trim();
  if (!input) return '';
  if (/^https?:\/\//i.test(input)) return input;
  if (!/\s/.test(input) && /^([a-z0-9-]+\.)+[a-z]{2,}(:\d+)?(\/.*)?$/i.test(input)) return `https://${input}`;
  return `${search === 'google' ? 'https://www.google.com/search?q=' : 'https://duckduckgo.com/?q='}${encodeURIComponent(input)}`;
}
export function gothicScript(enabled: boolean, originalSites: string[] = []) {
  // Recolour each site's own rules instead of overriding layout, fonts or every container.
  // Use a private API namespace; do not replace a site's existing DarkReader global.
  return `(function(){var old=document.getElementById('nightfall-gothic-theme');if(old)old.remove();
    var engine=window.__nightfallThemeEngine;
    var enabled=${JSON.stringify(enabled)} && ${JSON.stringify(originalSites)}.indexOf(location.hostname.toLowerCase())===-1;
    try {
      if(!enabled){if(engine)engine.disable();return;}
      ${enabled ? `if(!engine){engine={};(function(exports,module,define){${themeEngineSource}\n})(engine,{},undefined);window.__nightfallThemeEngine=engine;
        engine.setFetchMethod(function(url){return window.fetch(url,{credentials:'same-origin'});});}` : ''}
      if(engine&&!engine.isEnabled())engine.enable({brightness:100,contrast:100,sepia:5,darkSchemeBackgroundColor:'#0c0d0e',darkSchemeTextColor:'#eee8dc'});
    }catch(error){if(engine){try{engine.disable();}catch(ignored){}}console.warn('Nightfall website styling unavailable; original appearance restored.');}
  })();true;`;
}
export const portals = [
  { title: 'Runable', caption: 'Your creative workspace', url: 'https://runable.com', icon: 'sparkles-outline' },
  { title: 'Stark Store', caption: 'Your apps, collected', url: 'https://navidrome.nas-server.co.uk/store', icon: 'cube-outline' },
  { title: 'Wikipedia', caption: 'Follow your curiosity', url: 'https://en.wikipedia.org', icon: 'library-outline' },
  { title: 'DuckDuckGo', caption: 'A quieter search', url: 'https://duckduckgo.com', icon: 'compass-outline' },
] as const;