export type Tab = { id: string; url: string; lastUrl?: string; title: string; private: boolean };
export type SavedPage = { id: string; url: string; title: string; date: number };
export type Download = { id: string; name: string; uri: string; date: number };
export type BrowserSettings = { gothic: boolean; search: 'duckduckgo' | 'google' };
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
export function gothicScript(enabled: boolean) {
  const css = `html{color-scheme:dark!important}body{background:#0c0d0e!important;color:#eee8dc!important}a{color:#c3a16a!important}article,main,section,header,footer,nav{background-color:#151617!important;color:#eee8dc!important}h1,h2,h3{font-family:Georgia,serif!important}input,textarea,select{background:#1d1e20!important;color:#eee8dc!important;border-color:#5f5039!important}`;
  return `(function(){var id='nightfall-gothic-theme',s=document.getElementById(id);if(s)s.remove();${enabled ? `s=document.createElement('style');s.id=id;s.textContent=${JSON.stringify(css)};document.head.appendChild(s);` : ''}})();true;`;
}
export const portals = [
  { title: 'Runable', caption: 'Your creative workspace', url: 'https://runable.com', icon: 'sparkles-outline' },
  { title: 'Stark Store', caption: 'Your apps, collected', url: 'https://navidrome.nas-server.co.uk/store', icon: 'cube-outline' },
  { title: 'Wikipedia', caption: 'Follow your curiosity', url: 'https://en.wikipedia.org', icon: 'library-outline' },
  { title: 'DuckDuckGo', caption: 'A quieter search', url: 'https://duckduckgo.com', icon: 'compass-outline' },
] as const;