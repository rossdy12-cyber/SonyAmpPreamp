import XCTest

/// Mirrors the desktop app's engine tests (test/engine.test.js) so both sides
/// provably implement the same merge rules.
final class DuoSyncEngineTests: XCTestCase {

    // MARK: - Helpers

    private func hash(_ character: Character) -> String {
        String(repeating: String(character), count: 64)
    }

    private func entry(_ character: Character) -> FileEntry {
        FileEntry(hash: hash(character), size: 10, mtime: 1)
    }

    private func plan(
        local: [String: FileEntry] = [:],
        remote: [String: FileEntry] = [:],
        base: [String: String] = [:],
        mode: SyncMode = .twoWay
    ) -> (ops: [SyncOp], base: [String: String]) {
        Engine.plan(local: local, remote: remote, base: base, mode: mode)
    }

    private func kinds(_ ops: [SyncOp]) -> [String] {
        ops.map { op in
            switch op {
            case .rebase(let path, _): return "rebase:\(path)"
            case .recycle(let path, _): return "recycleTo:\(path)"
            case .saveFromRemote(let path, _, _): return "saveFromRemote:\(path)"
            case .pull(let path, _): return "pull:\(path)"
            case .push(let path, _): return "push:\(path)"
            case .pushConflict(let path, _): return "pushConflict:\(path)"
            case .deleteRemote(let path): return "delRemote:\(path)"
            case .deleteLocal(let path): return "delLocal:\(path)"
            }
        }
    }

    // MARK: - Tests

    func testIdenticalReplicasRecordAgreementWithoutWork() {
        let first = plan(local: ["a.txt": entry("a")], remote: ["a.txt": entry("a")])
        XCTAssertEqual(kinds(first.ops), ["rebase:a.txt"])
        XCTAssertEqual(first.base["a.txt"], hash("a"))

        let again = plan(local: ["a.txt": entry("a")], remote: ["a.txt": entry("a")], base: ["a.txt": hash("a")])
        XCTAssertEqual(kinds(again.ops), [])
    }

    func testNewLocalFileIsPushed() {
        let result = plan(local: ["new.txt": entry("a")])
        XCTAssertEqual(kinds(result.ops), ["push:new.txt"])
        guard case .push(_, let pushed) = result.ops[0] else { return XCTFail("wrong op") }
        XCTAssertEqual(pushed, hash("a"))
    }

    func testNewRemoteFileIsPulled() {
        XCTAssertEqual(kinds(plan(remote: ["new.txt": entry("b")]).ops), ["pull:new.txt"])
    }

    func testEditsPropagateBothWays() {
        XCTAssertEqual(
            kinds(plan(local: ["f": entry("c")], remote: ["f": entry("a")], base: ["f": hash("a")]).ops),
            ["push:f"]
        )
        XCTAssertEqual(
            kinds(plan(local: ["f": entry("a")], remote: ["f": entry("c")], base: ["f": hash("a")]).ops),
            ["pull:f"]
        )
    }

    func testUnchangedLocalIsNeverRewritten() {
        XCTAssertEqual(
            kinds(plan(local: ["f": entry("a")], remote: ["f": entry("a")], base: ["f": hash("a")]).ops),
            []
        )
    }

    func testDeletionsPropagate() {
        XCTAssertEqual(
            kinds(plan(remote: ["f": entry("a")], base: ["f": hash("a")]).ops),
            ["delRemote:f"]
        )
        XCTAssertEqual(
            kinds(plan(local: ["f": entry("a")], base: ["f": hash("a")]).ops),
            ["delLocal:f"]
        )
    }

    func testEditBeatsDeletion() {
        XCTAssertEqual(kinds(plan(local: ["f": entry("c")], base: ["f": hash("a")]).ops), ["push:f"])
        XCTAssertEqual(kinds(plan(remote: ["f": entry("c")], base: ["f": hash("a")]).ops), ["pull:f"])
    }

    func testBothEditedKeepsLoserBesideWinner() {
        let localWins = plan(local: ["f": entry("f")], remote: ["f": entry("b")], base: ["f": hash("a")])
        XCTAssertEqual(kinds(localWins.ops), ["saveFromRemote:f", "push:f"])
        XCTAssertEqual(localWins.base[Engine.conflictName("f", hash: hash("b"))], hash("b"))

        let remoteWins = plan(local: ["f": entry("b")], remote: ["f": entry("f")], base: ["f": hash("a")])
        let loser = Engine.conflictName("f", hash: hash("b"))
        XCTAssertEqual(kinds(remoteWins.ops), ["recycleTo:f", "pull:f", "pushConflict:\(loser)"])
    }

    func testConflictResolutionIsDeterministicOnBothReplicas() {
        let base = ["f": hash("a")]
        let onA = plan(local: ["f": entry("1")], remote: ["f": entry("9")], base: base)
        let onB = plan(local: ["f": entry("9")], remote: ["f": entry("1")], base: base)
        let loser = Engine.conflictName("f", hash: hash("1"))
        XCTAssertEqual(kinds(onA.ops), ["recycleTo:f", "pull:f", "pushConflict:\(loser)"])
        XCTAssertEqual(kinds(onB.ops), ["saveFromRemote:f", "push:f"])
    }

    func testPlansConvergeOnTheSameFileSet() {
        let base = ["f": hash("a")]
        let aLocal = ["f": entry("f")]
        let bLocal = ["f": entry("b")]
        let onA = plan(local: aLocal, remote: bLocal, base: base)
        let onB = plan(local: bLocal, remote: aLocal, base: base)
        let conflict = Engine.conflictName("f", hash: hash("b"))

        XCTAssertEqual(onA.base["f"], hash("f"))
        XCTAssertEqual(onA.base[conflict], hash("b"))
        XCTAssertEqual(onB.base["f"], hash("f"))
        XCTAssertEqual(onB.base[conflict], hash("b"))
        XCTAssertEqual(Set(onA.base.keys), Set(["f", conflict]))
    }

    func testPushModeIgnoresRemoteEdits() {
        let result = plan(local: ["f": entry("a")], remote: ["f": entry("z")], mode: .push)
        XCTAssertEqual(kinds(result.ops), ["push:f"])
    }

    func testPullModeIgnoresLocalEdits() {
        XCTAssertEqual(kinds(plan(local: ["f": entry("z")], remote: ["f": entry("a")], mode: .pull).ops), ["pull:f"])
    }

    func testOperationsAreOrderedSoDownloadsPrecedeOverwrites() {
        let ops = plan(remote: ["a": entry("a"), "b": entry("b")]).ops
        let ranks = ops.map(\.rank)
        XCTAssertEqual(ranks, ranks.sorted())
    }

    func testNestedAndUnicodePathsSurvivePlanning() {
        XCTAssertEqual(kinds(plan(local: ["deep/dir/ünïcode name.txt": entry("a")]).ops), ["push:deep/dir/ünïcode name.txt"])
    }

    func testConflictNamesKeepExtensionAndFolder() {
        XCTAssertEqual(Engine.conflictName("a/b/c.txt", hash: hash("9")), "a/b/c (conflict 99999999).txt")
        XCTAssertEqual(Engine.conflictName("noext", hash: hash("9")), "noext (conflict 99999999)")
    }

    func testCommittedBaselineDropsDeletedPaths() {
        let deleted = plan(local: ["f": entry("a")], base: ["f": hash("a")])
        XCTAssertEqual(kinds(deleted.ops), ["delLocal:f"])
        XCTAssertNil(deleted.base["f"])
    }

    func testIgnoreRulesMatchTheDesktopDefaults() {
        let isIgnored = Ignore.matcher(Ignore.defaults)
        XCTAssertTrue(isIgnored("Thumbs.db", "Thumbs.db"))
        XCTAssertTrue(isIgnored("~$draft.docx", "docs/~$draft.docx"))
        XCTAssertTrue(isIgnored("notes.tmp", "notes.tmp"))
        XCTAssertTrue(isIgnored(".duosync.tmp.abc123", ".duosync.tmp.abc123"))
        XCTAssertFalse(isIgnored("report.docx", "report.docx"))
        XCTAssertFalse(isIgnored("docs", "docs"))
    }

    func testConflictNameFormatMatchesDesktop() {
        // The Windows app builds this from the same rule; a mismatch would make
        // the two devices fight over names.
        let path = "photos/IMG 01.JPG"
        let name = Engine.conflictName(path, hash: "abcdef1234567890")
        XCTAssertEqual(name, "photos/IMG 01 (conflict abcdef12).JPG")
    }
}
