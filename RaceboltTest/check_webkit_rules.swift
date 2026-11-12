// Remote macOS preflight only. Does not build/sign an iOS app or access the shop.
import Foundation
import CoreFoundation
import AppKit
import WebKit
import Darwin

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("WebKit safety preflight FAILED: " + message + "\n").utf8))
    exit(22)
}
guard CommandLine.arguments.count == 2 else { fail("Expected path to LiveSafetyRules.json") }
let source: String
do { source = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8) }
catch { fail(error.localizedDescription) }
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let store = WKContentRuleListStore.default()
let identifier = "RaceboltBuildPreflight-v3-\(UUID().uuidString)"
store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: source) { list, error in
    guard let list = list, error == nil else {
        let e = error as NSError?
        fail("\(e?.domain ?? "unknown") code \(e?.code ?? -1): \(e?.localizedDescription ?? "No compiled rule list returned")")
    }
    print("PASS: Apple WebKit compiled checkout safety rules (\(list.identifier)).")
    store.removeContentRuleList(forIdentifier: identifier) { error in
        if let error = error { print("Preflight cache cleanup warning: \(error.localizedDescription)") }
        exit(0)
    }
}
DispatchQueue.main.asyncAfter(deadline: .now() + 60) { fail("Content rule compiler timed out after 60 seconds") }
CFRunLoopRun()
fail("Run loop ended before WebKit compilation completed")