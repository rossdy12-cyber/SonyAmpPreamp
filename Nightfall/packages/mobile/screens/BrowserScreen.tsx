import React, { useEffect, useRef, useState } from 'react';
import { View, Text, Pressable, TextInput, ScrollView, StyleSheet, Modal, KeyboardAvoidingView, Platform, Share, Linking, Switch, ActivityIndicator } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import BrowserView, { type BrowserHandle } from '../components/BrowserView';
import { useBrowser } from '../hooks/use-browser';
import { palette as c, portals, hostname, siteHost, address } from '../lib/browser';
import { downloadFile, shareFile, deleteFile } from '../lib/device-files';

type Icon = React.ComponentProps<typeof Ionicons>['name'];
type Sheet = 'tabs' | 'library' | 'settings' | 'downloads' | null;
type Nav = { url: string; title: string; back: boolean; forward: boolean; loading: boolean };
const display = 'Cinzel_400Regular', body = 'Inter_400Regular';

function IconButton({ icon, label, onPress, disabled = false, active = false }: { icon: Icon; label: string; onPress: () => void; disabled?: boolean; active?: boolean }) {
  return <Pressable onPress={onPress} disabled={disabled} accessibilityRole="button" accessibilityLabel={label} style={({ pressed }) => [s.iconButton, active && { backgroundColor: c.raised }, { opacity: disabled ? .25 : pressed ? .55 : 1 }]}><Ionicons name={icon} size={22} color={active ? c.gold : c.text} /></Pressable>;
}

export default function BrowserScreen() {
  const b = useBrowser();
  const [sheet, setSheet] = useState<Sheet>(null);
  const [library, setLibrary] = useState<'bookmarks' | 'history'>('bookmarks');
  const [input, setInput] = useState('');
  const [editing, setEditing] = useState(false);
  const [message, setMessage] = useState('');
  const [confirmation, setConfirmation] = useState<null | (() => void)>(null);
  const [confirmationText, setConfirmationText] = useState('');
  const [navs, setNavs] = useState<Record<string, Nav>>({});
  const [downloadUrl, setDownloadUrl] = useState('');
  const [downloading, setDownloading] = useState(false);
  const refs = useRef<Record<string, BrowserHandle | null>>({});
  const nav = navs[b.activeId];
  const currentUrl = b.active.url ? (nav?.url || b.active.url) : '';
  const currentTitle = b.active.url ? (nav?.title || b.active.title) : b.active.title;
  const currentBookmarked = b.bookmarks.some(p => p.url === currentUrl);
  const currentHost = siteHost(currentUrl);
  const currentOriginalSites = b.active.private ? b.privateOriginalSites : b.settings.originalSites;
  const toggleOriginalAppearance = (original: boolean) => {
    if (!currentHost) return;
    const update = (sites: string[]) => original ? [...new Set([...sites, currentHost])] : sites.filter(host => host !== currentHost);
    if (b.active.private) b.setPrivateOriginalSites(update);
    else b.setSettings(old => ({ ...old, originalSites: update(old.originalSites) }));
  };
  const { storageError, setStorageError } = b;
  useEffect(() => { if (!editing) setInput(currentUrl); }, [currentUrl, b.activeId, editing]);
  useEffect(() => { if (!message) return; const timer = setTimeout(() => setMessage(''), 7000); return () => clearTimeout(timer); }, [message]);
  useEffect(() => { if (storageError) { setMessage(storageError); setStorageError(''); } }, [storageError, setStorageError]);
  const confirm = (text: string, action: () => void) => { setConfirmationText(text); setConfirmation(() => action); };
  const open = (url: string) => { b.navigate(url); setInput(url); setEditing(false); setSheet(null); };
  const external = (url: string) => { confirm('This link opens another app. That app uses its own session and privacy settings. Continue?', () => { Linking.openURL(url).catch(() => setMessage('No app is available to open this link.')); }); };
  const sharePage = async () => { if (!currentUrl) return; try { await Share.share({ message: currentUrl, url: Platform.OS === 'ios' ? currentUrl : undefined }); } catch { setMessage('Sharing is unavailable on this device.'); } };
  const download = async (url: string) => {
    if (downloading) return;
    setDownloading(true);
    try { const file = await downloadFile(url); b.setDownloads(old => [file, ...old]); setMessage(`Saved ${file.name}. Find it in Downloads.`); setDownloadUrl(''); }
    catch (err) { setMessage(err instanceof Error ? err.message : 'Download failed.'); }
    finally { setDownloading(false); }
  };
  const offerDownload = (url: string) => confirm('Save this file to Nightfall? Downloads remain on your device, even from a private tab. Cookie-protected files may require Safari.', () => { void download(url); });
  const privateToggle = () => {
    const target = b.tabs.find(t => t.private !== b.active.private);
    if (target) b.setActiveId(target.id); else b.addTab(!b.active.private);
  };
  const chooseTab = (id: string) => { b.setActiveId(id); setSheet(null); };

  if (!b.ready) return <SafeAreaView style={s.screen}><ActivityIndicator color={c.gold} style={{ flex: 1 }} /></SafeAreaView>;
  return <SafeAreaView edges={['top', 'left', 'right', 'bottom']} style={s.screen}>
    <KeyboardAvoidingView behavior={Platform.OS === 'ios' ? 'padding' : 'height'} style={{ flex: 1 }}>
      <View style={s.header}>
        <Pressable onPress={b.home} accessibilityRole="button" accessibilityLabel="Nightfall home" style={s.brand}><View style={s.brandGlyph}><Ionicons name="moon-outline" size={17} color={c.gold} /></View><Text style={s.wordmark}>NIGHTFALL</Text></Pressable>
        <View style={s.row}><IconButton icon={b.active.private ? 'eye-off-outline' : 'moon-outline'} label="Toggle private browsing" active={b.active.private} onPress={privateToggle} /><IconButton icon="options-outline" label="Settings" onPress={() => setSheet('settings')} /></View>
      </View>
      {b.active.private && <View style={s.privateBar}><Ionicons name="eye-off-outline" size={13} color={c.gold} /><Text style={s.privateBarText}>PRIVATE SANCTUARY · NOT SAVED TO HISTORY</Text></View>}
      <View style={{ flex: 1 }}>
        {b.tabs.filter(t => t.url).map(tab => <View key={tab.id} style={[StyleSheet.absoluteFill, { display: tab.id === b.activeId ? 'flex' : 'none' }]}>
          <BrowserView ref={r => { refs.current[tab.id] = r; }} url={tab.url} private={tab.private} gothic={b.settings.gothic} originalSites={tab.private ? b.privateOriginalSites : b.settings.originalSites}
            onNavigate={state => { setNavs(old => ({ ...old, [tab.id]: state })); b.updateNavigation(tab.id, state); }}
            onNewTab={url => { if (/^https?:/i.test(url)) b.addTab(tab.private, url); }} onExternal={external} onDownload={offerDownload} onError={setMessage} />
        </View>)}
        {!b.active.url && <ScrollView style={{ flex: 1 }} contentContainerStyle={s.home} keyboardShouldPersistTaps="handled">
          <View style={s.overline}><View style={s.line} /><Text style={s.eyebrow}>{b.active.private ? 'LEAVE NO TRAIL' : 'YOUR PERSONAL SANCTUARY'}</Text><View style={s.line} /></View>
          <View style={s.archOuter}><View style={s.archInner}><View style={s.archCenter}><Ionicons name={b.active.private ? 'eye-off-outline' : 'moon-outline'} size={43} color={c.gold} /><View style={s.archStem} /><View style={s.diamond} /></View></View><View style={s.archFoot} /></View>
          <Text style={s.hero}>{b.active.private ? 'A moment\njust for you.' : 'The quieter side\nof the web.'}</Text>
          <Text style={s.subtitle}>{b.active.private ? 'An ephemeral session. No saved tabs or history.' : 'Less noise. More wonder. Browse on your terms.'}</Text>
          <View style={s.sectionHeading}><Text style={s.sectionLabel}>QUICK PASSAGES</Text><Text style={s.smallGold}>01 — 04</Text></View>
          <View style={s.portals}>{portals.map(p => <Pressable key={p.title} accessibilityRole="button" onPress={() => open(p.url)} style={({ pressed }) => [s.portal, pressed && { backgroundColor: c.raised }]}>
            <View style={s.portalTop}><Ionicons name={p.icon} size={21} color={c.gold} /><Ionicons name="arrow-up-outline" size={16} color={c.muted} style={{ transform: [{ rotate: '45deg' }] }} /></View>
            <Text style={s.portalTitle}>{p.title}</Text><Text style={s.portalCaption}>{p.caption}</Text>
          </Pressable>)}</View>
          <View style={s.sectionHeading}><Text style={s.sectionLabel}>YOUR COLLECTION</Text><Pressable onPress={() => { setLibrary('bookmarks'); setSheet('library'); }} accessibilityRole="button" style={{ paddingVertical: 10 }}><Text style={s.smallGold}>View all →</Text></Pressable></View>
          {b.bookmarks.length ? b.bookmarks.slice(0, 3).map(page => <Pressable key={page.id} onPress={() => open(page.url)} style={s.collection}><Ionicons name="bookmark-outline" size={18} color={c.gold} /><View style={{ flex: 1 }}><Text style={s.itemTitle} numberOfLines={1}>{page.title}</Text><Text style={s.itemCaption}>{hostname(page.url)}</Text></View><Ionicons name="chevron-forward" size={15} color={c.muted} /></Pressable>) : <View style={s.collectionEmpty}><Ionicons name="bookmark-outline" size={18} color={c.muted} /><Text style={s.emptySmall}>Keep the places worth returning to.</Text></View>}
          <View style={s.homeFooter}><View style={s.diamondSmall} /><Text style={s.footerCopy}>CRAFTED FOR THE CURIOUS</Text><View style={s.diamondSmall} /></View>
        </ScrollView>}
      </View>
      {!!message && <Pressable onPress={() => setMessage('')} style={s.notice} accessibilityLabel="Dismiss notification"><Text style={s.noticeText}>{message}</Text><Ionicons name="close" size={16} color={c.gold} /></Pressable>}
      <View style={s.bottom}>
        {nav?.loading && <View style={s.loadingLine} />}
        <View style={[s.address, b.active.private && { borderColor: '#634252' }]}>
          <Ionicons name={b.active.private ? 'eye-off-outline' : currentUrl ? (currentUrl.startsWith('https:') ? 'lock-closed-outline' : 'warning-outline') : 'search-outline'} size={17} color={c.gold} />
          <TextInput value={input} onChangeText={setInput} onFocus={() => { setEditing(true); setInput(currentUrl); }} onBlur={() => setEditing(false)} onSubmitEditing={() => open(input)} placeholder="Search or enter an address" placeholderTextColor={c.muted} autoCapitalize="none" autoCorrect={false} keyboardType="url" returnKeyType="go" selectTextOnFocus style={s.addressInput} accessibilityLabel="Search or enter an address" />
          <IconButton icon={editing ? 'arrow-forward' : 'reload-outline'} label={editing ? 'Go to address' : 'Reload page'} onPress={() => editing ? open(input) : refs.current[b.activeId]?.reload()} />
        </View>
        <View style={s.toolbar}>
          <IconButton icon="chevron-back" label="Back" disabled={!nav?.back || !b.active.url} onPress={() => refs.current[b.activeId]?.back()} />
          <IconButton icon="chevron-forward" label="Forward" disabled={!nav?.forward || !b.active.url} onPress={() => refs.current[b.activeId]?.forward()} />
          <IconButton icon="share-outline" label="Share page" disabled={!currentUrl} onPress={sharePage} />
          <IconButton icon={currentBookmarked ? 'bookmark' : 'bookmark-outline'} label={currentUrl ? 'Save or remove bookmark' : 'Open bookmarks'} active={currentBookmarked} onPress={() => { if (currentUrl) b.saveBookmark(currentUrl, currentTitle || hostname(currentUrl)); else { setLibrary('bookmarks'); setSheet('library'); } }} />
          <Pressable onPress={() => setSheet('tabs')} accessibilityRole="button" accessibilityLabel={`Open ${b.tabs.length} tabs`} style={s.iconButton}><View style={s.tabCount}><Text style={s.tabCountText}>{b.tabs.length}</Text></View></Pressable>
        </View>
      </View>
    </KeyboardAvoidingView>

    <Modal visible={sheet !== null} animationType="slide" onRequestClose={() => setSheet(null)}>
      <SafeAreaView style={s.screen} edges={['top', 'left', 'right', 'bottom']}>
        <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === 'ios' ? 'padding' : 'height'}>
          <View style={s.sheetHeader}><View><Text style={s.eyebrow}>NIGHTFALL</Text><Text style={s.sheetTitle}>{sheet === 'tabs' ? 'Open passages' : sheet === 'library' ? 'Your collection' : sheet === 'settings' ? 'Make it yours' : 'Downloads'}</Text></View><IconButton icon="close-outline" label="Close panel" onPress={() => setSheet(null)} /></View>
          <ScrollView contentContainerStyle={s.sheetBody} keyboardShouldPersistTaps="handled">
            {sheet === 'tabs' && <>
              <View style={s.tabActions}><Pressable accessibilityRole="button" style={s.goldButton} onPress={() => { b.addTab(false); setSheet(null); }}><Ionicons name="add" size={19} color={c.bg} /><Text style={s.goldButtonText}>New tab</Text></Pressable><Pressable accessibilityRole="button" style={s.outlineButton} onPress={() => { b.addTab(true); setSheet(null); }}><Ionicons name="eye-off-outline" size={17} color={c.gold} /><Text style={s.outlineText}>Private tab</Text></Pressable></View>
              <Text style={s.help}>{b.tabs.length} of 12 tabs · Private tabs disappear when the app closes.</Text>
              {b.tabs.map(tab => <View key={tab.id} style={[s.tabCard, tab.id === b.activeId && { borderColor: c.gold }, tab.private && { backgroundColor: '#21171C' }]}><Pressable onPress={() => chooseTab(tab.id)} style={{ flex: 1, padding: 18 }} accessibilityRole="button"><View style={s.row}><Ionicons name={tab.private ? 'eye-off-outline' : 'globe-outline'} size={19} color={c.gold} /><Text style={s.tabLabel}>{tab.private ? 'PRIVATE' : 'STANDARD'}{tab.id === b.activeId ? ' · ACTIVE' : ''}</Text></View><Text style={s.tabTitle} numberOfLines={2}>{tab.title}</Text><Text style={s.itemCaption} numberOfLines={1}>{tab.url ? hostname(tab.url) : 'Nightfall home'}</Text></Pressable><IconButton icon="close" label={`Close ${tab.title}`} onPress={() => b.closeTab(tab.id)} /></View>)}
              {b.tabs.some(t => t.private) && <Pressable style={s.outlineButton} onPress={() => { b.closePrivateTabs(); setSheet(null); }}><Text style={s.outlineText}>Close all private tabs</Text></Pressable>}
            </>}
            {sheet === 'library' && <>
              <View style={s.segment}>{(['bookmarks', 'history'] as const).map(k => <Pressable key={k} onPress={() => setLibrary(k)} style={[s.segmentButton, library === k && { backgroundColor: c.raised }]}><Text style={[s.segmentText, library === k && { color: c.gold }]}>{k === 'bookmarks' ? 'Bookmarks' : 'History'}</Text></Pressable>)}</View>
              {(library === 'bookmarks' ? b.bookmarks : b.history).map(page => <View style={s.listItem} key={page.id}><Pressable onPress={() => open(page.url)} style={{ flex: 1 }}><Text style={s.itemTitle} numberOfLines={2}>{page.title}</Text><Text style={s.itemCaption} numberOfLines={1}>{hostname(page.url)}{library === 'history' ? ` · ${new Date(page.date).toLocaleDateString()}` : ''}</Text></Pressable><IconButton icon="close-outline" label={`Remove ${page.title}`} onPress={() => library === 'bookmarks' ? b.setBookmarks(old => old.filter(p => p.id !== page.id)) : b.setHistory(old => old.filter(p => p.id !== page.id))} /></View>)}
              {!(library === 'bookmarks' ? b.bookmarks : b.history).length && <View style={s.empty}><Ionicons name={library === 'bookmarks' ? 'bookmark-outline' : 'time-outline'} size={35} color={c.gold} /><Text style={s.emptyTitle}>{library === 'bookmarks' ? 'A collection awaits.' : 'A fresh beginning.'}</Text><Text style={s.emptyText}>{library === 'bookmarks' ? 'Visit a page and tap the bookmark icon to save it here.' : 'Your non-private browsing history will appear here.'}</Text></View>}
              {library === 'history' && b.history.length > 0 && <Pressable style={s.outlineButton} onPress={() => confirm('Clear all browsing history? This cannot be undone.', () => b.setHistory([]))}><Text style={s.outlineText}>Clear browsing history</Text></Pressable>}
            </>}
            {sheet === 'settings' && <>
              <Text style={s.sectionLabel}>APPEARANCE</Text>
              <View style={s.settingRow}><View style={{ flex: 1 }}><Text style={s.itemTitle}>Gothic website styling</Text><Text style={s.settingCopy}>Optional dark-and-ivory colours that preserve website fonts and layout. Turn off for original website colours.</Text></View><Switch accessibilityLabel="Gothic website styling" value={b.settings.gothic} onValueChange={gothic => b.setSettings(old => ({ ...old, gothic }))} trackColor={{ false: c.border, true: '#675233' }} thumbColor={c.gold} /></View>
              {!!currentHost && <View style={s.settingRow}><View style={{ flex: 1 }}><Text style={s.itemTitle}>Original appearance for this site</Text><Text style={s.settingCopy}>{currentHost}{b.active.private ? '\nOnly remembered during private browsing.' : '\nRemembered for this hostname.'} Use if a page looks wrong.</Text></View><Switch accessibilityLabel="Original appearance for this site" value={currentOriginalSites.includes(currentHost)} onValueChange={toggleOriginalAppearance} trackColor={{ false: c.border, true: '#675233' }} thumbColor={c.gold} /></View>}
              {!!b.settings.originalSites.length && <Pressable style={s.settingRow} onPress={() => confirm('Remove all saved original-appearance exceptions? Websites will follow your Gothic styling setting.', () => b.setSettings(old => ({ ...old, originalSites: [] })))} accessibilityRole="button" accessibilityLabel="Reset site appearance exceptions"><Text style={[s.itemTitle, { flex: 1 }]}>Reset site appearance exceptions</Text><Text style={s.help}>{b.settings.originalSites.length}</Text></Pressable>}
              <Text style={[s.sectionLabel, { marginTop: 30 }]}>SEARCH ENGINE</Text>
              {(['duckduckgo', 'google'] as const).map(search => <Pressable key={search} style={s.settingRow} onPress={() => b.setSettings(old => ({ ...old, search }))}><Text style={[s.itemTitle, { flex: 1 }]}>{search === 'google' ? 'Google' : 'DuckDuckGo'}</Text><Ionicons name={b.settings.search === search ? 'radio-button-on' : 'radio-button-off'} size={22} color={c.gold} /></Pressable>)}
              <Text style={[s.sectionLabel, { marginTop: 30 }]}>BROWSER TOOLS</Text>
              <Pressable style={s.settingRow} onPress={() => setSheet('downloads')}><Ionicons name="download-outline" size={20} color={c.gold} /><Text style={[s.itemTitle, { flex: 1 }]}>Downloads</Text><Text style={s.help}>{b.downloads.length}</Text><Ionicons name="chevron-forward" size={18} color={c.muted} /></Pressable>
              <Pressable style={s.settingRow} onPress={() => { setLibrary('history'); setSheet('library'); }}><Ionicons name="time-outline" size={20} color={c.gold} /><Text style={[s.itemTitle, { flex: 1 }]}>History</Text><Ionicons name="chevron-forward" size={18} color={c.muted} /></Pressable>
              <View style={s.privacyCard}><Ionicons name="shield-checkmark-outline" size={24} color={c.gold} /><Text style={s.privacyTitle}>Private, not invisible.</Text><Text style={s.settingCopy}>Private tabs use an ephemeral WebKit session and aren’t saved to Nightfall’s history. Websites and your network can still see your activity. Bookmarks you explicitly save and downloaded files are kept.</Text></View>
              <Text style={s.help}>Nightfall 1.0.1 · Built for iPhone{Platform.OS === 'web' ? '\nYou are viewing the interactive web preview.' : ''}</Text>
              <Text style={s.help}>Some providers block sign-in inside embedded browsers. Nightfall cannot override provider security or guarantee Apple/Google login. Browser settings do not clear website cookies.</Text>
            </>}
            {sheet === 'downloads' && <>
              <Text style={s.help}>Save a public HTTP/HTTPS file to your iPhone, then share it to Files or another app. Authenticated website downloads may require Safari.</Text>
              <TextInput value={downloadUrl} onChangeText={setDownloadUrl} placeholder="https://example.com/file.pdf" placeholderTextColor={c.muted} style={s.downloadInput} autoCapitalize="none" autoCorrect={false} keyboardType="url" accessibilityLabel="Download URL" />
              <Pressable disabled={!downloadUrl || downloading} style={[s.goldButton, (!downloadUrl || downloading) && { opacity: .4 }]} onPress={() => { const url = address(downloadUrl, b.settings.search); if (!/^https?:\/\//.test(downloadUrl)) { setMessage('Enter a complete HTTP or HTTPS file URL.'); return; } void download(url); }}><Ionicons name="download-outline" size={19} color={c.bg} /><Text style={s.goldButtonText}>{downloading ? 'Downloading…' : 'Download file'}</Text></Pressable>
              {b.downloads.map(file => <View style={s.listItem} key={file.id}><Ionicons name="document-outline" size={24} color={c.gold} /><View style={{ flex: 1 }}><Text style={s.itemTitle}>{file.name}</Text><Text style={s.itemCaption}>{new Date(file.date).toLocaleDateString()}</Text></View><IconButton icon="share-outline" label={`Share ${file.name}`} onPress={() => { shareFile(file.uri).catch(err => setMessage(String(err.message))); }} /><IconButton icon="trash-outline" label={`Delete ${file.name}`} onPress={() => confirm(`Delete ${file.name} from your device?`, () => { deleteFile(file.uri).then(() => b.setDownloads(old => old.filter(d => d.id !== file.id))).catch(() => setMessage('Could not delete the file.')); })} /></View>)}
              {!b.downloads.length && <View style={s.empty}><Ionicons name="download-outline" size={34} color={c.gold} /><Text style={s.emptyTitle}>Nothing gathered yet.</Text><Text style={s.emptyText}>Your downloaded files will live here.</Text></View>}
            </>}
          </ScrollView>
          {!!message && <Pressable style={s.notice} onPress={() => setMessage('')}><Text style={s.noticeText}>{message}</Text></Pressable>}
        </KeyboardAvoidingView>
      </SafeAreaView>
    </Modal>
    <Modal transparent visible={!!confirmation} animationType="fade" onRequestClose={() => setConfirmation(null)}><View style={s.confirmShade}><View style={s.confirmCard}><Text style={s.emptyTitle}>One moment.</Text><Text style={s.emptyText}>{confirmationText}</Text><View style={[s.row, { marginTop: 25, justifyContent: 'flex-end' }]}><Pressable style={s.outlineButton} onPress={() => setConfirmation(null)}><Text style={s.outlineText}>Cancel</Text></Pressable><Pressable style={s.goldButton} onPress={() => { confirmation?.(); setConfirmation(null); }}><Text style={s.goldButtonText}>Continue</Text></Pressable></View></View></View></Modal>
  </SafeAreaView>;
}

const s = StyleSheet.create({
  screen: { flex: 1, backgroundColor: c.bg }, row: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  header: { height: 70, paddingHorizontal: 23, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', borderBottomWidth: 1, borderBottomColor: c.border },
  brand: { flexDirection: 'row', gap: 12, alignItems: 'center', minHeight: 44 }, brandGlyph: { width: 28, height: 35, borderWidth: 1, borderColor: c.gold, borderTopLeftRadius: 15, borderTopRightRadius: 15, alignItems: 'center', justifyContent: 'center' }, wordmark: { fontFamily: display, letterSpacing: 3.3, fontSize: 19, color: c.text },
  iconButton: { width: 44, height: 44, alignItems: 'center', justifyContent: 'center', borderRadius: 6 },
  privateBar: { backgroundColor: c.wine, paddingVertical: 9, flexDirection: 'row', justifyContent: 'center', alignItems: 'center', gap: 7 }, privateBarText: { color: c.text, fontFamily: 'Inter_500Medium', fontSize: 9, letterSpacing: 1.3 },
  home: { paddingHorizontal: 25, paddingTop: 34, paddingBottom: 25 }, overline: { flexDirection: 'row', alignItems: 'center', gap: 13 }, line: { flex: 1, height: 1, backgroundColor: '#4B4030' }, eyebrow: { fontFamily: 'Inter_500Medium', color: c.gold, fontSize: 9, letterSpacing: 2 },
  archOuter: { marginTop: 28, alignSelf: 'center', width: 116, height: 139, borderWidth: 1, borderColor: '#766144', borderTopLeftRadius: 59, borderTopRightRadius: 59, padding: 7 }, archInner: { flex: 1, borderWidth: 1, borderColor: '#453D30', borderTopLeftRadius: 54, borderTopRightRadius: 54 }, archCenter: { flex: 1, alignItems: 'center', paddingTop: 29 }, archStem: { width: 1, height: 18, backgroundColor: '#736044', marginTop: 6 }, diamond: { width: 6, height: 6, backgroundColor: c.gold, transform: [{ rotate: '45deg' }] }, archFoot: { position: 'absolute', width: 144, height: 1, backgroundColor: '#766144', bottom: -1, left: -15 },
  hero: { fontFamily: display, fontSize: 36, lineHeight: 47, letterSpacing: -.7, color: c.text, textAlign: 'center', marginTop: 26 }, subtitle: { fontFamily: body, fontSize: 12, lineHeight: 19, color: c.muted, textAlign: 'center', marginTop: 11 },
  sectionHeading: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginTop: 31, marginBottom: 14 }, sectionLabel: { fontFamily: 'Inter_500Medium', fontSize: 10, letterSpacing: 1.8, color: c.muted }, smallGold: { fontFamily: body, fontSize: 10, color: c.gold },
  portals: { flexDirection: 'row', flexWrap: 'wrap', gap: 10 }, portal: { width: '48.3%', flexGrow: 1, padding: 17, backgroundColor: c.panel, borderWidth: 1, borderColor: c.border, borderRadius: 3 }, portalTop: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginBottom: 21 }, portalTitle: { fontFamily: display, fontSize: 15, color: c.text }, portalCaption: { fontFamily: body, fontSize: 9, marginTop: 7, color: c.muted },
  collection: { flexDirection: 'row', alignItems: 'center', gap: 15, borderBottomWidth: 1, borderBottomColor: c.border, paddingVertical: 15 }, collectionEmpty: { borderWidth: 1, borderStyle: 'dashed', borderColor: c.border, padding: 18, flexDirection: 'row', alignItems: 'center', gap: 12 }, emptySmall: { color: c.muted, fontSize: 11, fontFamily: body }, homeFooter: { flexDirection: 'row', justifyContent: 'center', alignItems: 'center', gap: 12, marginTop: 29 }, diamondSmall: { width: 3, height: 3, backgroundColor: c.gold, transform: [{ rotate: '45deg' }] }, footerCopy: { fontFamily: body, color: '#6B665D', fontSize: 8, letterSpacing: 2 },
  bottom: { backgroundColor: '#101112', borderTopWidth: 1, borderTopColor: c.border, paddingHorizontal: 16, paddingTop: 13 }, address: { flexDirection: 'row', alignItems: 'center', borderWidth: 1, borderColor: '#443C30', backgroundColor: '#1A1B1C', paddingLeft: 15, height: 49, borderRadius: 6, gap: 10 }, addressInput: { flex: 1, color: c.text, fontFamily: body, fontSize: 12, paddingVertical: 12, minWidth: 0, outlineStyle: 'none' } as any, toolbar: { flexDirection: 'row', justifyContent: 'space-between', paddingVertical: 5, paddingHorizontal: 3 }, tabCount: { width: 21, height: 22, borderWidth: 1.5, borderColor: c.text, borderRadius: 3, alignItems: 'center', justifyContent: 'center' }, tabCountText: { fontFamily: 'Inter_500Medium', fontSize: 11, color: c.text }, loadingLine: { height: 2, width: '65%', backgroundColor: c.gold, position: 'absolute', top: 0, left: 0 },
  notice: { padding: 14, backgroundColor: '#2C251B', flexDirection: 'row', gap: 10, alignItems: 'center' }, noticeText: { fontFamily: body, fontSize: 12, color: c.text, lineHeight: 19, flex: 1 },
  sheetHeader: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 25, paddingVertical: 25, borderBottomWidth: 1, borderBottomColor: c.border }, sheetTitle: { fontFamily: display, fontSize: 26, color: c.text, marginTop: 9 }, sheetBody: { padding: 25, paddingBottom: 40 }, tabActions: { flexDirection: 'row', gap: 10, marginBottom: 12 },
  goldButton: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 8, backgroundColor: c.gold, paddingHorizontal: 17, paddingVertical: 14, borderRadius: 3, minHeight: 44 }, goldButtonText: { fontFamily: 'Inter_600SemiBold', color: c.bg, fontSize: 12 }, outlineButton: { borderWidth: 1, borderColor: '#554633', flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 8, paddingHorizontal: 16, paddingVertical: 13, borderRadius: 3, minHeight: 44 }, outlineText: { color: c.gold, fontFamily: 'Inter_500Medium', fontSize: 12 },
  help: { fontFamily: body, fontSize: 11, lineHeight: 19, color: c.muted, marginBottom: 18 }, tabCard: { backgroundColor: c.panel, borderWidth: 1, borderColor: c.border, marginBottom: 13, borderRadius: 5, flexDirection: 'row', alignItems: 'flex-start', paddingRight: 5 }, tabLabel: { fontFamily: 'Inter_500Medium', fontSize: 9, letterSpacing: 1.5, color: c.muted }, tabTitle: { fontFamily: display, fontSize: 19, color: c.text, marginTop: 17, marginBottom: 8 },
  segment: { flexDirection: 'row', backgroundColor: c.panel, padding: 4, marginBottom: 20, borderRadius: 5 }, segmentButton: { flex: 1, paddingVertical: 13, alignItems: 'center', borderRadius: 3 }, segmentText: { color: c.muted, fontFamily: 'Inter_500Medium', fontSize: 12 }, listItem: { flexDirection: 'row', alignItems: 'center', gap: 10, borderBottomWidth: 1, borderBottomColor: c.border, paddingVertical: 14 }, itemTitle: { fontFamily: 'Inter_500Medium', fontSize: 13, color: c.text, lineHeight: 19 }, itemCaption: { fontFamily: body, fontSize: 10, color: c.muted, lineHeight: 17, marginTop: 5 }, empty: { alignItems: 'center', marginVertical: 55, gap: 16 }, emptyTitle: { fontFamily: display, fontSize: 23, color: c.text, textAlign: 'center' }, emptyText: { fontFamily: body, fontSize: 13, color: c.muted, lineHeight: 22, textAlign: 'center', maxWidth: 340 }, settingRow: { flexDirection: 'row', alignItems: 'center', gap: 14, paddingVertical: 20, borderBottomWidth: 1, borderBottomColor: c.border }, settingCopy: { fontFamily: body, fontSize: 11, color: c.muted, lineHeight: 20, marginTop: 8 }, privacyCard: { backgroundColor: c.panel, borderWidth: 1, borderColor: c.border, padding: 21, marginVertical: 28 }, privacyTitle: { fontFamily: display, fontSize: 20, color: c.text, marginTop: 13 }, downloadInput: { borderWidth: 1, borderColor: c.border, padding: 14, borderRadius: 3, color: c.text, fontFamily: body, fontSize: 12, marginBottom: 12 },
  confirmShade: { flex: 1, justifyContent: 'center', padding: 24, backgroundColor: '#000000BB' }, confirmCard: { padding: 24, backgroundColor: c.panel, borderWidth: 1, borderColor: '#554633', borderRadius: 5, alignSelf: 'center', width: '100%', maxWidth: 430, gap: 15 },
});