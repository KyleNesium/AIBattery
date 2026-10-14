import Foundation
import Testing
@testable import AIBatteryCore

@Suite("AccountCard")
struct AccountCardTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func rec(
        _ id: String, _ provider: AIProvider,
        name: String? = nil, billing: String? = nil, apiKey: Bool = false
    ) -> AccountRecord {
        AccountRecord(
            id: id, displayName: name, billingType: billing, addedAt: now,
            provider: provider, codexAccessMode: apiKey ? .apiKey : nil
        )
    }

    private func windowReading(
        _ five: Double, _ seven: Double,
        throttled: Bool = false, resetIn: TimeInterval = 3_600,
        provider: AIProvider = .claude, cached: Bool = false
    ) -> AccountReading {
        let rl = RateLimitUsage(
            representativeClaim: RateLimitUsage.fiveHourWindow,
            fiveHourUtilization: five, fiveHourReset: now.addingTimeInterval(resetIn),
            fiveHourStatus: throttled ? "throttled" : "allowed",
            sevenDayUtilization: seven, sevenDayReset: now.addingTimeInterval(resetIn * 24),
            sevenDayStatus: "allowed",
            overallStatus: throttled ? "throttled" : "allowed",
            provider: provider
        )
        return AccountReading(windows: rl, apiLimits: nil, fetchedAt: now, isCached: cached, source: nil)
    }

    private func status(_ indicator: StatusIndicator) -> ClaudeSystemStatus {
        ClaudeSystemStatus(indicator: indicator, description: "", incidentNames: [], statusPageURL: "")
    }

    // MARK: - Ordering, identity, the number a card leads with

    @Test func rows_claudeFirst_activeFlag_worstPercent_andWindowLabels() {
        let accounts = [
            rec("x1", .codex, name: "Work Codex", billing: "business"),
            rec("c1", .claude, name: "Claude Team"),
        ]
        let cards = AccountCard.rows(
            accounts: accounts, activeId: "x1",
            readings: ["c1": windowReading(0.34, 0.26), "x1": windowReading(0.12, 0.08, provider: .codex)],
            statuses: [:], isAuthenticated: { _ in true }, maskEmail: true, now: now
        )
        #expect(cards.map(\.id) == ["c1", "x1"])
        #expect(cards[0].isActive == false)
        #expect(cards[1].isActive)
        #expect(cards[0].identity == "Claude Team")
        #expect(cards[0].worstPercent == 34)
        #expect(cards[0].plan == nil) // plan label is Codex-only
        #expect(cards[1].plan == "Business")
        #expect(cards[0].bars.map(\.label) == ["5-Hour", "7-Day"])
        #expect(cards[1].bars.map(\.label) == ["5-Hour", "Weekly"])
        #expect(cards[0].state == .none)
    }

    @Test func rows_carryProviderStatusOntoEveryCard() {
        let accounts = [rec("c1", .claude), rec("x1", .codex)]
        let cards = AccountCard.rows(
            accounts: accounts, activeId: "c1",
            readings: ["c1": windowReading(0.1, 0.1), "x1": windowReading(0.1, 0.1, provider: .codex)],
            statuses: [.claude: status(.operational), .codex: status(.partialOutage)],
            isAuthenticated: { _ in true }, maskEmail: true, now: now
        )
        #expect(cards[0].status == .operational)
        #expect(cards[1].status == .partialOutage)
    }

    // MARK: - Eligibility

    @Test func rows_signedOutIsASignInCard_pendingHidden() {
        let accounts = [rec("c1", .claude), rec("c2", .claude), rec("pending-9", .codex)]
        let cards = AccountCard.rows(
            accounts: accounts, activeId: "c1", readings: ["c1": windowReading(0.1, 0.1)],
            statuses: [:], isAuthenticated: { $0 != "c2" }, maskEmail: true, now: now
        )
        #expect(cards.map(\.id) == ["c1", "c2"])
        #expect(cards[1].state == .signedOut)
        #expect(cards[1].bars.isEmpty)
        #expect(cards[1].worstPercent == nil)
        // A signed-out account still counts: the overview is where you notice it.
        #expect(AccountCard.eligibleCount(accounts: accounts) == 2)
    }

    // MARK: - State precedence

    @Test func rows_statePrecedence_throttledOverCached() {
        let accounts = [rec("c1", .claude), rec("c2", .claude)]
        let throttled = windowReading(1.0, 0.2, throttled: true)
        let cached = windowReading(0.5, 0.2, cached: true)
        let cards = AccountCard.rows(
            accounts: accounts, activeId: "c1", readings: ["c1": throttled, "c2": cached],
            statuses: [:], isAuthenticated: { _ in true }, maskEmail: true, now: now
        )
        #expect(cards[0].state == .throttled)
        #expect(cards[1].state == .cached(now))
    }

    @Test func rows_cachedData_neverAlarms() {
        // A cached 100% must not read "Limit reached" — same gate the bars use.
        let accounts = [rec("c1", .claude)]
        let cards = AccountCard.rows(
            accounts: accounts, activeId: "c1",
            readings: ["c1": windowReading(1.0, 0.2, cached: true)],
            statuses: [:], isAuthenticated: { _ in true }, maskEmail: true, now: now
        )
        #expect(cards[0].state == .cached(now))
    }

    @Test func rows_noReadingYet_isFetching_withEmptyBars() {
        let accounts = [rec("c1", .claude), rec("k1", .codex, apiKey: true)]
        let cards = AccountCard.rows(
            accounts: accounts, activeId: "c1", readings: [:],
            statuses: [:], isAuthenticated: { _ in true }, maskEmail: true, now: now
        )
        #expect(cards[0].state == .fetching)
        #expect(cards[0].worstPercent == nil)
        #expect(cards[0].bars.map(\.label) == ["5-Hour", "7-Day"])
        #expect(cards[0].bars.allSatisfy { $0.percent == nil })
        // An API-key account keeps its own row shape before the first probe lands.
        #expect(cards[1].bars.map(\.label) == ["Requests", "Tokens"])
    }

    // MARK: - Quota shapes

    @Test func rows_creditsAndApiKinds() throws {
        let budget = CodexCreditBudget(
            usedPercent: 61, used: 61, limit: 100, remaining: 39, unit: "credit",
            resetsAt: now.addingTimeInterval(12 * 86_400), reached: false,
            hasCredits: true, unlimited: false, planType: "business"
        )
        let credits = RateLimitUsage(
            representativeClaim: "credits",
            fiveHourUtilization: 0.61, fiveHourReset: nil, fiveHourStatus: "allowed",
            sevenDayUtilization: 0.61, sevenDayReset: nil, sevenDayStatus: "allowed",
            overallStatus: "allowed", provider: .codex, creditBudget: budget
        )
        let std = try #require(StandardRateLimits.parse(openAIHeaders: [
            "x-ratelimit-limit-requests": "100", "x-ratelimit-remaining-requests": "20",
            "x-ratelimit-limit-tokens": "1000", "x-ratelimit-remaining-tokens": "900",
        ], now: now))
        let accounts = [rec("x1", .codex, billing: "business"), rec("k1", .codex, billing: "api", apiKey: true)]
        let cards = AccountCard.rows(
            accounts: accounts, activeId: "x1",
            readings: [
                "x1": AccountReading(windows: credits, apiLimits: nil, fetchedAt: now, isCached: false, source: nil),
                "k1": AccountReading(windows: nil, apiLimits: std, fetchedAt: now, isCached: false, source: nil),
            ],
            statuses: [.codex: status(.operational)],
            isAuthenticated: { _ in true }, maskEmail: true, now: now
        )
        #expect(cards[0].bars.map(\.label) == ["Credits"])
        #expect(cards[0].bars[0].percent == 61)
        #expect(cards[0].worstPercent == 61)
        #expect(cards[1].bars.map(\.label) == ["Requests", "Tokens"])
        #expect(cards[1].worstPercent == 80)
    }

    @Test func rows_uncappedCredits_haveNoPercent() {
        let budget = CodexCreditBudget(
            usedPercent: 0, used: 0, limit: 0, remaining: 0, unit: "credit", resetsAt: nil,
            reached: false, hasCredits: true, unlimited: false, planType: "business", uncapped: true
        )
        let credits = RateLimitUsage(
            representativeClaim: "credits",
            fiveHourUtilization: 0, fiveHourReset: nil, fiveHourStatus: "allowed",
            sevenDayUtilization: 0, sevenDayReset: nil, sevenDayStatus: "allowed",
            overallStatus: "allowed", provider: .codex, creditBudget: budget
        )
        let cards = AccountCard.rows(
            accounts: [rec("x1", .codex)], activeId: "x1",
            readings: ["x1": AccountReading(windows: credits, apiLimits: nil, fetchedAt: now, isCached: false, source: nil)],
            statuses: [:], isAuthenticated: { _ in true }, maskEmail: true, now: now
        )
        #expect(cards[0].bars[0].uncapped)
        #expect(cards[0].bars[0].percent == nil)
        #expect(cards[0].worstPercent == nil)
    }

    // MARK: - Text

    @Test func stateText_formats() {
        #expect(AccountCard.stateText(.throttled, now: now) == "Throttled")
        #expect(AccountCard.stateText(.limitReached, now: now) == "Limit reached")
        #expect(AccountCard.stateText(.signedOut, now: now) == "Signed out · click to sign in")
        #expect(AccountCard.stateText(.timeToLimit(2 * 3_600), now: now)?.hasPrefix("~") == true)
        #expect(AccountCard.stateText(.cached(now.addingTimeInterval(-180)), now: now) == "Cached 3m ago")
        #expect(AccountCard.stateText(.fetching, now: now) == "Fetching…")
        #expect(AccountCard.stateText(.none, now: now) == nil)
    }

    @Test func accessibilityLabel_namesProviderIdentityPlanAndWindows() {
        let cards = AccountCard.rows(
            accounts: [rec("x1", .codex, name: "Work", billing: "business")], activeId: "x1",
            readings: ["x1": windowReading(0.34, 0.26, provider: .codex)],
            statuses: [.codex: status(.operational)],
            isAuthenticated: { _ in true }, maskEmail: true, now: now
        )
        let label = cards[0].accessibilityLabel
        #expect(label.contains("Codex account Work"))
        #expect(label.contains("Business"))
        #expect(label.contains("active"))
        #expect(label.contains("5-Hour 34 percent"))
        #expect(label.contains("Weekly 26 percent"))
        #expect(label.contains("status operational"))
    }
}
