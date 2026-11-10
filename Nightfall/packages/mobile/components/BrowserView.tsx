import React, { forwardRef, useImperativeHandle, useRef, useEffect } from 'react';
import { WebView } from 'react-native-webview';
import type { WebViewNavigation } from 'react-native-webview';
import { gothicScript } from '../lib/browser';

export type BrowserHandle = { back: () => void; forward: () => void; reload: () => void };
export type BrowserProps = { url: string; private: boolean; gothic: boolean; onNavigate: (state: { url: string; title: string; back: boolean; forward: boolean; loading: boolean }) => void; onNewTab: (url: string) => void; onDownload: (url: string) => void; onExternal: (url: string) => void; onError: (message: string) => void };

const BrowserView = forwardRef<BrowserHandle, BrowserProps>((props, ref) => {
  const web = useRef<WebView>(null);
  useImperativeHandle(ref, () => ({ back: () => web.current?.goBack(), forward: () => web.current?.goForward(), reload: () => web.current?.reload() }));
  useEffect(() => { web.current?.injectJavaScript(gothicScript(props.gothic)); }, [props.gothic]);
  const navigate = (state: WebViewNavigation) => props.onNavigate({ url: state.url, title: state.title, back: state.canGoBack, forward: state.canGoForward, loading: state.loading });
  return <WebView
    ref={web} source={{ uri: props.url }} style={{ flex: 1, backgroundColor: '#0C0D0E' }}
    incognito={props.private} sharedCookiesEnabled={!props.private} thirdPartyCookiesEnabled={!props.private}
    javaScriptEnabled allowsBackForwardNavigationGestures allowsInlineMediaPlayback
    originWhitelist={['http://*', 'https://*']} setSupportMultipleWindows
    onOpenWindow={e => props.onNewTab(e.nativeEvent.targetUrl)}
    onNavigationStateChange={navigate}
    injectedJavaScript={gothicScript(props.gothic)}
    onLoadEnd={() => web.current?.injectJavaScript(gothicScript(props.gothic))}
    onFileDownload={e => props.onDownload(e.nativeEvent.downloadUrl)}
    onShouldStartLoadWithRequest={request => {
      if (/^https?:/i.test(request.url) || request.url === 'about:blank') return true;
      props.onExternal(request.url); return false;
    }}
    onError={e => props.onError(e.nativeEvent.description)}
    onHttpError={e => { if (e.nativeEvent.statusCode >= 500) props.onError(`Website returned HTTP ${e.nativeEvent.statusCode}`); }}
    allowsLinkPreview={!props.private}
  />;
});
export default BrowserView;