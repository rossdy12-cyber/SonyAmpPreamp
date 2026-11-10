import { useEffect, useRef, useState } from 'react';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { address, makeTab, makeId, restoreSettings, type Tab, type SavedPage, type Download, type BrowserSettings } from '../lib/browser';
const KEY = 'nightfall.browser.v1';
export function useBrowser() {
  const first = useRef(makeTab()).current;
  const [tabs, setTabs] = useState<Tab[]>([first]);
  const [activeId, setActiveId] = useState(first.id);
  const [bookmarks, setBookmarks] = useState<SavedPage[]>([]);
  const [history, setHistory] = useState<SavedPage[]>([]);
  const [downloads, setDownloads] = useState<Download[]>([]);
  const [settings, setSettings] = useState<BrowserSettings>(restoreSettings());
  const [privateOriginalSites, setPrivateOriginalSites] = useState<string[]>([]);
  const [ready, setReady] = useState(false);
  const [storageError, setStorageError] = useState('');
  useEffect(() => { let mounted = true;
    AsyncStorage.getItem(KEY).then(raw => {
      if (!raw || !mounted) return;
      const data = JSON.parse(raw);
      const saved = Array.isArray(data.tabs) ? data.tabs.filter((t: Tab) => !t.private && typeof t.id === 'string' && typeof t.url === 'string') : [];
      if (saved.length) { setTabs(saved); setActiveId(saved.some((t: Tab) => t.id === data.activeId) ? data.activeId : saved[0].id); }
      if (Array.isArray(data.bookmarks)) setBookmarks(data.bookmarks);
      if (Array.isArray(data.history)) setHistory(data.history);
      if (Array.isArray(data.downloads)) setDownloads(data.downloads);
      if (data.settings) setSettings(restoreSettings(data.settings));
    }).catch(() => setStorageError('Saved browser data could not be loaded.')).finally(() => { if (mounted) setReady(true); });
    return () => { mounted = false; };
  }, []);
  useEffect(() => {
    if (!ready) return;
    const timer = setTimeout(() => { AsyncStorage.setItem(KEY, JSON.stringify({ tabs: tabs.filter(t => !t.private).map(t => ({ ...t, url: t.lastUrl || t.url })), activeId, bookmarks, history, downloads, settings })).catch(() => setStorageError('Browser data could not be saved.')); }, 250);
    return () => clearTimeout(timer);
  }, [ready, tabs, activeId, bookmarks, history, downloads, settings]);
  const active = tabs.find(t => t.id === activeId) || tabs[0];
  useEffect(() => { if (!tabs.some(t => t.private)) setPrivateOriginalSites([]); }, [tabs]);
  const addTab = (isPrivate = active.private, url = '') => {
    if (tabs.length >= 12) { setStorageError('Close a tab before opening another (12-tab limit).'); return; }
    const tab = makeTab(isPrivate, url); setTabs(old => [...old, tab]); setActiveId(tab.id); return tab.id;
  };
  const closeTab = (id: string) => {
    const remaining = tabs.filter(t => t.id !== id);
    if (!remaining.length) { const tab = makeTab(); setTabs([tab]); setActiveId(tab.id); }
    else { setTabs(remaining); if (activeId === id) setActiveId(remaining[remaining.length - 1].id); }
  };
  const navigate = (input: string) => { const url = address(input, settings.search); if (url) setTabs(old => old.map(t => t.id === activeId ? { ...t, url, lastUrl: url, title: url } : t)); };
  const updateNavigation = (id: string, state: { url: string; title: string; loading: boolean }) => {
    if (!/^https?:/i.test(state.url)) return;
    setTabs(old => old.map(t => t.id === id ? { ...t, lastUrl: state.url, title: state.title || t.title } : t));
    const tab = tabs.find(t => t.id === id);
    if (!state.loading && tab && !tab.private) setHistory(old => {
      if (old[0]?.url === state.url) return old;
      return [{ id: makeId(), url: state.url, title: state.title || state.url, date: Date.now() }, ...old].slice(0, 200);
    });
  };
  const saveBookmark = (url: string, title: string) => {
    setBookmarks(old => old.some(b => b.url === url) ? old.filter(b => b.url !== url) : [{ id: makeId(), url, title, date: Date.now() }, ...old]);
  };
  return { tabs, active, activeId, setActiveId, addTab, closeTab, navigate, updateNavigation,
    bookmarks, setBookmarks, saveBookmark, history, setHistory, downloads, setDownloads,
    settings, setSettings, privateOriginalSites, setPrivateOriginalSites, ready, storageError, setStorageError,
    closePrivateTabs: () => { const normal = tabs.filter(t => !t.private); const next = normal.length ? normal : [makeTab()]; setTabs(next); setActiveId(next[0].id); },
    home: () => setTabs(old => old.map(t => t.id === activeId ? { ...t, url: '', lastUrl: '', title: 'New sanctuary' } : t)) };
}