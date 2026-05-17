import Testing
import Foundation

/// Pins the v2.3.1 "no `.move(edge:)` inside the popover" rule.
///
/// The popover is an NSPanel whose top edge is re-anchored to the menu bar
/// button on every height change. A `.move(edge:)` transition translates the
/// inserting/removing view in roughly the same direction the panel itself is
/// moving, and the two motions fight each other — the user reads it as a
/// "jump". Fixed in v2.3.1 by switching every site to `.opacity` and locking
/// `MotionConstants.expandTransition` to plain `.opacity` with a doc-comment
/// banning the regression.
///
/// This test walks the actual `AIBattery/Views/` source tree and fails if any
/// view file reintroduces `.move(edge:`. New views can opt-in by editing the
/// allow list below with an explicit rationale.
@Suite("MoveTransitionBan")
struct MoveTransitionBanTests {
    /// Absolute path to the source tree we're auditing. Tests run from the
    /// package root (`swift test` working directory), so we can derive it from
    /// the current file. `#filePath` is the canonical path of this test source.
    private static var viewsDirectory: URL {
        let testFile = URL(fileURLWithPath: #filePath)
        return testFile
            .deletingLastPathComponent() // Views/
            .deletingLastPathComponent() // AIBatteryCoreTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // package root
            .appendingPathComponent("AIBattery")
            .appendingPathComponent("Views")
    }

    /// Relative paths inside Views/ that are explicitly allowed to use
    /// `.move(edge:)`. Empty by design — add an entry with a comment if a
    /// future feature genuinely needs the slide AND has demonstrated it
    /// doesn't trigger the NSPanel resize race.
    private static let allowList: Set<String> = []

    @Test func noViewFile_usesMoveEdgeTransition() {
        let fm = FileManager.default
        let viewsDir = Self.viewsDirectory.path

        guard fm.fileExists(atPath: viewsDir) else {
            Issue.record("Views/ directory not found at \(viewsDir); test path resolution drifted")
            return
        }

        let enumerator = fm.enumerator(atPath: viewsDir)
        var offenders: [String] = []

        while let relativePath = enumerator?.nextObject() as? String {
            guard relativePath.hasSuffix(".swift") else { continue }
            if Self.allowList.contains(relativePath) { continue }

            let fullPath = (viewsDir as NSString).appendingPathComponent(relativePath)
            guard let contents = try? String(contentsOfFile: fullPath, encoding: .utf8) else {
                continue
            }

            // Match `.move(edge:` even with whitespace variations. The pattern
            // is intentionally permissive — any literal use anywhere in the
            // file triggers, including inside comments. If you really need to
            // discuss .move in a comment, rephrase or move it to a Markdown
            // doc.
            if contents.contains(".move(edge:") {
                offenders.append(relativePath)
            }
        }

        #expect(offenders.isEmpty, """
        Views/ files reintroduced `.move(edge:)`. The popover's NSPanel resizes \
        around inserting views and any directional translate reads as a "jump". \
        Use `.transition(.opacity)` or `MotionConstants.expandTransition`. \
        If your case is a deliberate exception, document why and add the path \
        to MoveTransitionBanTests.allowList.

        Offending files: \(offenders.joined(separator: ", "))
        """)
    }
}
