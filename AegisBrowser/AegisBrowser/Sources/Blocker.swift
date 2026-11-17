import Foundation
import WebKit

// MARK: - Content blocker + injected scripts

enum Blocker {
    static let ruleListID = "aegis-blocker-v1"

    static func loadRuleList(completion: @escaping (WKContentRuleList?) -> Void) {
        guard let url = Bundle.main.url(forResource: "blocker", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = String(data: data, encoding: .utf8) else {
            completion(nil); return
        }
        WKContentRuleListStore.default().lookUpContentRuleList(forIdentifier: ruleListID) { list, _ in
            if let list { completion(list); return }
            WKContentRuleListStore.default().compileContentRuleList(forIdentifier: ruleListID, encodedContentRuleList: json) { list, err in
                completion(list)
            }
        }
    }

    // Injected at document start: defines helpers used by the rest of the app.
    static let bootstrapJS = """
    window.__aegisSetDark = function(on) {
        if (on) {
            if (!document.getElementById('aegis-dark-style')) {
                var s = document.createElement('style');
                s.id = 'aegis-dark-style';
                s.textContent = 'html{filter:invert(1) hue-rotate(180deg) contrast(0.92) brightness(1.05)!important;}' +
                    'img,video,picture,svg,canvas,iframe,[style*="background-image"]{filter:invert(1) hue-rotate(180deg)!important;}';
                document.documentElement.appendChild(s);
            }
        } else {
            document.getElementById('aegis-dark-style')?.remove();
        }
    };
    window.__aegisSetZoom = function(pct) {
        document.documentElement.style.webkitTextSizeAdjust = pct === 100 ? '' : pct + '%';
    };
    """

    // Long-press context menu for links/images -> native message handler
    static let contextMenuJS = """
    (function(){
        if (window.__aegisMenuInstalled) return;
        window.__aegisMenuInstalled = true;
        var handler = function(e){
            var el = e.target.closest ? e.target.closest('a[href]') : null;
            var img = e.target.closest ? e.target.closest('img') : null;
            if (!el && !img) return;
            var href = el ? el.href : (img ? img.src : null);
            if (!href) return;
            e.preventDefault();
            window.webkit.messageHandlers.aegisMenu.postMessage({href: href, isImage: !!img && !el});
        };
        document.addEventListener('contextmenu', handler, true);
    })();
    """

    // Find-in-page helpers
    static let findJS = """
    window.__aegisFind = {
        spans: [],
        query: '',
        _clear: function(){
            this.spans.forEach(function(s){
                var p = s.parentNode;
                if (p) { p.replaceChild(document.createTextNode(s.textContent), s); p.normalize(); }
            });
            this.spans = [];
        },
        count: function(q){
            this._clear(); this.query = q;
            if (!q) return 0;
            var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null, false);
            var node, total = 0, self = this;
            var low = q.toLowerCase();
            while ((node = walker.nextNode())) {
                if (!node.nodeValue) continue;
                var text = node.nodeValue, tl = text.toLowerCase(), idx = tl.indexOf(low);
                if (idx === -1) continue;
                var frag = document.createDocumentFragment(), pos = 0;
                while (idx !== -1) {
                    frag.appendChild(document.createTextNode(text.slice(pos, idx)));
                    var mark = document.createElement('mark');
                    mark.style.background = '#DC143C'; mark.style.color = '#fff';
                    mark.textContent = text.substr(idx, q.length);
                    frag.appendChild(mark); self.spans.push(mark);
                    total++; pos = idx + q.length;
                    idx = tl.indexOf(low, pos);
                }
                frag.appendChild(document.createTextNode(text.slice(pos)));
                node.parentNode.replaceChild(frag, node);
            }
            return total;
        },
        step: function(dir){
            if (!this.spans.length) return;
            this._current = ((this._current || 0) + dir + this.spans.length) % this.spans.length;
            this.spans.forEach(function(s){ s.style.outline = ''; });
            var cur = this.spans[this._current];
            cur.style.outline = '3px solid #fff';
            cur.scrollIntoView({block: 'center', behavior: 'smooth'});
        }
    };
    """
}

// MARK: - URL helpers

enum OmniboxLogic {
    static func resolve(_ raw: String, engine: DataStore.SearchEngine) -> (url: URL, isSearch: Bool) {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.isEmpty, let u = URL(string: s), let scheme = u.scheme?.lowercased(),
           scheme == "http" || scheme == "https" || scheme == "about" {
            return (u, false)
        }
        if s.contains(" "), let u = URL(string: "https://\(s.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? s)") {
            // "two words" is usually a search
        }
        let hostLike = !s.isEmpty && !s.contains(" ") && (s.contains(".") && !s.hasSuffix(".")) && s.range(of: "^[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}(:\\d+)?(/.*)?$", options: .regularExpression) != nil
        if hostLike {
            return (URL(string: "https://" + s)!, false)
        }
        let q = s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
        return (URL(string: String(format: engine.template, q))!, true)
    }

    static func prettyURL(_ url: URL?) -> String {
        guard var s = url?.absoluteString else { return "" }
        if s.hasPrefix("https://") { s.removeFirst(8) }
        else if s.hasPrefix("http://") { s.removeFirst(7) }
        return s
    }
}
