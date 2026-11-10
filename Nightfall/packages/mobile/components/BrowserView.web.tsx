import React, { forwardRef, useEffect, useImperativeHandle, useRef } from 'react';
import { View, Text, Pressable, StyleSheet, Linking } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import type { BrowserHandle, BrowserProps } from './BrowserView';
import { hostname, palette as c } from '../lib/browser';

const BrowserView = forwardRef<BrowserHandle, BrowserProps>((props, ref) => {
  const navigate = useRef(props.onNavigate);
  navigate.current = props.onNavigate;
  const url = props.url;
  useImperativeHandle(ref, () => ({ back: () => {}, forward: () => {}, reload: () => {} }));
  useEffect(() => { navigate.current({ url, title: hostname(url), back: false, forward: false, loading: false }); }, [url]);
  return <View style={s.wrap}>
    <View style={s.mark}><Ionicons name="phone-portrait-outline" size={34} color={c.gold} /></View>
    <Text style={s.label}>IPHONE BROWSING</Text>
    <Text style={s.title}>{hostname(props.url)}</Text>
    <Text style={s.copy}>This preview lets you try Nightfall’s controls. On your iPhone, this page opens inside the browser with its own WebKit session.</Text>
    <Text style={s.url}>{props.url}</Text>
    <Pressable style={s.button} onPress={() => Linking.openURL(props.url)} accessibilityRole="button"><Text style={s.buttonText}>Open in this device’s browser</Text><Ionicons name="open-outline" size={17} color={c.gold} /></Pressable>
    {props.private && <Text style={s.note}>Private tabs are not saved in Nightfall. Opening an external browser uses that browser’s own session.</Text>}
  </View>;
});
const s = StyleSheet.create({ wrap: { flex: 1, alignItems: 'center', justifyContent: 'center', padding: 30, backgroundColor: c.bg }, mark: { width: 76, height: 96, borderWidth: 1, borderColor: c.gold, borderTopLeftRadius: 40, borderTopRightRadius: 40, alignItems: 'center', justifyContent: 'center', marginBottom: 30 }, label: { fontFamily: 'Inter_500Medium', fontSize: 10, letterSpacing: 3, color: c.gold }, title: { fontFamily: 'Cinzel_400Regular', fontSize: 27, color: c.text, marginTop: 15, textAlign: 'center' }, copy: { fontFamily: 'Inter_400Regular', fontSize: 14, color: c.muted, lineHeight: 23, textAlign: 'center', marginTop: 20, maxWidth: 400 }, url: { color: c.muted, fontSize: 12, marginTop: 20, maxWidth: '100%' }, button: { flexDirection: 'row', gap: 12, padding: 16, borderWidth: 1, borderColor: c.border, marginTop: 30, alignItems: 'center' }, buttonText: { color: c.gold, fontFamily: 'Inter_500Medium', fontSize: 12 }, note: { color: c.muted, fontSize: 11, textAlign: 'center', marginTop: 20, lineHeight: 18 } });
export default BrowserView;