import Foundation
import Testing
@testable import AIBatteryCore

@Suite("ProjectIdentityResolver")
struct ProjectIdentityTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("project-identity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - gitdir parsing

    @Test func parentRepo_readsTheGitdirLine() {
        let contents = "gitdir: /Users/kyle/repo/.git/worktrees/feature-x\n"
        #expect(ProjectIdentityResolver.parentRepo(fromGitFile: contents) == "/Users/kyle/repo")
    }

    @Test func parentRepo_ignoresAnythingThatIsNotAWorktreePointer() {
        // A submodule's `.git` file points at the superproject's modules dir, not a worktree.
        #expect(ProjectIdentityResolver.parentRepo(fromGitFile: "gitdir: ../.git/modules/sub") == nil)
        #expect(ProjectIdentityResolver.parentRepo(fromGitFile: "nonsense") == nil)
        #expect(ProjectIdentityResolver.parentRepo(fromGitFile: "") == nil)
    }

    // MARK: - Identity

    @Test func identity_plainDirectoryUsesItsOwnPathAndName() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let identity = try #require(ProjectIdentityResolver.resolve(cwd: dir.path))
        #expect(identity.displayName == dir.lastPathComponent)
        #expect(identity.key == dir.resolvingSymlinksInPath().path)
    }

    /// A worktree and its parent repo are one project: before this they appeared as two
    /// rows, each holding part of the same work.
    @Test func identity_worktreeFoldsIntoItsParentRepo() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = root.appendingPathComponent("myrepo")
        let worktree = root.appendingPathComponent("wt-feature")
        try FileManager.default.createDirectory(at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        try "gitdir: \(repo.path)/.git/worktrees/feature\n"
            .write(to: worktree.appendingPathComponent(".git"), atomically: true, encoding: .utf8)

        let fromWorktree = try #require(ProjectIdentityResolver.resolve(cwd: worktree.path))
        let fromRepo = try #require(ProjectIdentityResolver.resolve(cwd: repo.path))
        #expect(fromWorktree.key == fromRepo.key)
        #expect(fromWorktree.displayName == "myrepo")
    }

    @Test func identity_ordinaryCheckoutIsNotTreatedAsAWorktree() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = root.appendingPathComponent("plainrepo")
        try FileManager.default.createDirectory(at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true)
        let identity = try #require(ProjectIdentityResolver.resolve(cwd: repo.path))
        #expect(identity.key == repo.resolvingSymlinksInPath().path)
        #expect(identity.displayName == "plainrepo")
    }

    @Test func identity_symlinkedPathResolvesToTheSameProject() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let real = root.appendingPathComponent("real-project")
        let link = root.appendingPathComponent("link-to-project")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        let viaLink = try #require(ProjectIdentityResolver.resolve(cwd: link.path))
        let direct = try #require(ProjectIdentityResolver.resolve(cwd: real.path))
        #expect(viaLink.key == direct.key)
        #expect(viaLink.displayName == "real-project")
    }

    @Test func identity_rootAndEmptyPathsHaveNoProject() {
        #expect(ProjectIdentityResolver.resolve(cwd: "") == nil)
        #expect(ProjectIdentityResolver.resolve(cwd: "/") == nil)
    }

    @Test func identity_isCachedPerWorkingDirectory() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let resolver = ProjectIdentityResolver()
        let first = resolver.identity(for: dir.path)
        // Removing the directory must not change an answer already given: the cache is
        // what keeps the aggregation pass off the filesystem for repeat cwds.
        try FileManager.default.removeItem(at: dir)
        #expect(resolver.identity(for: dir.path) == first)
    }
}
