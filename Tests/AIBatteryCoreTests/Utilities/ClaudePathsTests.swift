import Foundation
import Testing
@testable import AIBatteryCore

@Suite("ClaudePaths")
struct ClaudePathsTests {

    @Test func statsCache_endsWithExpectedSuffix() {
        #expect(ClaudePaths.statsCache.path.hasSuffix(".claude/stats-cache.json"))
    }

    @Test func statsCachePath_matchesURL() {
        #expect(ClaudePaths.statsCachePath == ClaudePaths.statsCache.path)
    }

    @Test func projects_endsWithExpectedSuffix() {
        #expect(ClaudePaths.projects.path.hasSuffix(".claude/projects"))
    }

    @Test func projectsPath_matchesURL() {
        #expect(ClaudePaths.projectsPath == ClaudePaths.projects.path)
    }

    @Test func allPaths_areAbsolute() {
        #expect(ClaudePaths.statsCachePath.hasPrefix("/"))
        #expect(ClaudePaths.projectsPath.hasPrefix("/"))
    }
}
