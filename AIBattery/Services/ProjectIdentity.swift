import Foundation

/// Turns a session's `cwd` into the project it belongs to.
///
/// Project rows used to be keyed by the raw `cwd` and labelled with its last path
/// component, which made two different `api` directories indistinguishable and split a
/// git worktree away from the repository it belongs to — the same project appearing
/// twice, each with part of the usage. Two cheap rules fix both:
///
/// - **Symlinks are resolved**, so `/tmp/x` and `/private/tmp/x` are one project.
/// - **A git worktree folds into its parent repo.** A worktree's `.git` is a *file*
///   whose single line reads `gitdir: /path/to/repo/.git/worktrees/<name>`, so the
///   parent is readable without shelling out to git.
///
/// Results are cached for the process: a cwd's identity cannot change while the app is
/// running (a moved checkout gets a new cwd), and this runs on the aggregation thread.
final class ProjectIdentityResolver: @unchecked Sendable {
    static let shared = ProjectIdentityResolver()

    struct Identity: Equatable {
        /// Stable key for grouping — the parent repo for a worktree.
        let key: String
        /// What the row says.
        let displayName: String
    }

    private let lock = NSLock()
    private var cache: [String: Identity?] = [:]
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// The project for a working directory, or nil when the path carries no project
    /// name at all (an empty cwd, or `/`).
    func identity(for cwd: String) -> Identity? {
        lock.lock()
        if let cached = cache[cwd] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let resolved = Self.resolve(cwd: cwd, fileManager: fileManager)

        lock.lock()
        cache[cwd] = resolved
        lock.unlock()
        return resolved
    }

    /// Uncached resolution — the testable core.
    static func resolve(cwd: String, fileManager: FileManager = .default) -> Identity? {
        guard !cwd.isEmpty else { return nil }
        let resolved = URL(fileURLWithPath: cwd).resolvingSymlinksInPath().path
        let base = worktreeParent(of: resolved, fileManager: fileManager) ?? resolved
        let name = (base as NSString).lastPathComponent
        guard !name.isEmpty, name != "/" else { return nil }
        return Identity(key: base, displayName: name)
    }

    /// The repository a worktree belongs to, or nil when this is not a worktree.
    ///
    /// `<worktree>/.git` is a regular file containing
    /// `gitdir: /path/to/repo/.git/worktrees/<name>`; the repo root is everything before
    /// `/.git/worktrees/`. A `.git` *directory* is an ordinary checkout and resolves to
    /// itself.
    static func worktreeParent(of path: String, fileManager: FileManager = .default) -> String? {
        let dotGit = (path as NSString).appendingPathComponent(".git")
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: dotGit, isDirectory: &isDirectory), !isDirectory.boolValue,
              let contents = try? String(contentsOfFile: dotGit, encoding: .utf8) else { return nil }
        return parentRepo(fromGitFile: contents)
    }

    /// Parses the `gitdir:` line of a worktree's `.git` file.
    static func parentRepo(fromGitFile contents: String) -> String? {
        guard let line = contents.split(whereSeparator: \.isNewline)
            .first(where: { $0.hasPrefix("gitdir:") }) else { return nil }
        let gitDir = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        guard let range = gitDir.range(of: "/.git/worktrees/") else { return nil }
        let repo = String(gitDir[gitDir.startIndex..<range.lowerBound])
        return repo.isEmpty ? nil : repo
    }
}
