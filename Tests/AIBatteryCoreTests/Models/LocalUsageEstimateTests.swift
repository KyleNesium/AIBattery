import Testing
import Foundation
@testable import AIBatteryCore

@Suite("LocalUsageEstimate")
struct LocalUsageEstimateTests {
    // MARK: - calibrateFrom429 policy

    @MainActor
    @Test func calibrateFrom429_uncalibrated_seedsLimit() {
        let account = Self.makeAccountId()
        defer { Self.cleanup(account) }

        LocalUsageEstimate.latestFiveHourTokens = 1_000_000
        LocalUsageEstimate.latestSevenDayTokens = 0
        LocalUsageEstimate.calibrateFrom429(accountId: account, activeAccountId: account)

        // limit = 1_000_000 / 0.95 ≈ 1_052_631
        #expect(LocalUsageEstimate.fiveHourLimit(for: account) > 1_000_000)
        #expect(LocalUsageEstimate.fiveHourLimit(for: account) < 1_100_000)
    }

    @MainActor
    @Test func calibrateFrom429_existingCalibration_doesNotOverride() {
        let account = Self.makeAccountId()
        defer { Self.cleanup(account) }

        // Pre-existing calibration from a real headers-backed call.
        LocalUsageEstimate.setFiveHourLimit(5_000_000, for: account)
        LocalUsageEstimate.latestFiveHourTokens = 1_000_000
        LocalUsageEstimate.calibrateFrom429(accountId: account, activeAccountId: account)

        // Must not ratchet a precise calibration down from a header-less 429
        // (which may not even be a quota throttle).
        #expect(LocalUsageEstimate.fiveHourLimit(for: account) == 5_000_000)
    }

    @MainActor
    @Test func calibrateFrom429_belowMinTokenFloor_skipsSeeding() {
        let account = Self.makeAccountId()
        defer { Self.cleanup(account) }

        LocalUsageEstimate.latestFiveHourTokens = 50_000 // below 100_000 floor
        LocalUsageEstimate.calibrateFrom429(accountId: account, activeAccountId: account)

        #expect(LocalUsageEstimate.fiveHourLimit(for: account) == 0)
    }

    @MainActor
    @Test func calibrateFrom429_independentWindows() {
        let account = Self.makeAccountId()
        defer { Self.cleanup(account) }

        // 5h already calibrated (must not be touched), 7d uncalibrated (should seed).
        LocalUsageEstimate.setFiveHourLimit(3_000_000, for: account)
        LocalUsageEstimate.setSevenDayLimit(0, for: account)
        LocalUsageEstimate.latestFiveHourTokens = 1_000_000
        LocalUsageEstimate.latestSevenDayTokens = 1_000_000
        LocalUsageEstimate.calibrateFrom429(accountId: account, activeAccountId: account)

        #expect(LocalUsageEstimate.fiveHourLimit(for: account) == 3_000_000)
        #expect(LocalUsageEstimate.sevenDayLimit(for: account) > 1_000_000)
    }

    @MainActor
    @Test func calibrateFrom429_nonActiveAccount_neverSeeds() {
        // latest*Tokens hold the ACTIVE account's local counts — a fan-out 429
        // for another account must not seed that account from them.
        let fanOutAccount = Self.makeAccountId()
        let activeAccount = Self.makeAccountId()
        defer {
            Self.cleanup(fanOutAccount)
            Self.cleanup(activeAccount)
        }

        LocalUsageEstimate.latestFiveHourTokens = 1_000_000
        LocalUsageEstimate.calibrateFrom429(accountId: fanOutAccount, activeAccountId: activeAccount)

        #expect(LocalUsageEstimate.fiveHourLimit(for: fanOutAccount) == 0)
        #expect(LocalUsageEstimate.fiveHourLimit(for: activeAccount) == 0)
    }

    // MARK: - calibrate band (API utilization)

    @MainActor
    @Test func calibrate_midBand_setsLimit() {
        let account = Self.makeAccountId()
        defer { Self.cleanup(account) }

        // 50% utilization, 1M tokens → derived limit 2M.
        LocalUsageEstimate.calibrate(
            fiveHourUtilization: 0.50,
            sevenDayUtilization: 0,
            localFiveHourTokens: 1_000_000,
            localSevenDayTokens: 0,
            accountId: account
        )
        #expect(LocalUsageEstimate.fiveHourLimit(for: account) == 2_000_000)
    }

    @MainActor
    @Test func calibrate_belowBand_skips() {
        let account = Self.makeAccountId()
        defer { Self.cleanup(account) }

        // 10% is below the 20% band edge — dividing by it magnifies error, so skip.
        LocalUsageEstimate.calibrate(
            fiveHourUtilization: 0.10,
            sevenDayUtilization: 0,
            localFiveHourTokens: 1_000_000,
            localSevenDayTokens: 0,
            accountId: account
        )
        #expect(LocalUsageEstimate.fiveHourLimit(for: account) == 0)
    }

    @MainActor
    @Test func calibrate_aboveBand_skips() {
        let account = Self.makeAccountId()
        defer { Self.cleanup(account) }

        // 90% is above the 80% band edge — skip.
        LocalUsageEstimate.calibrate(
            fiveHourUtilization: 0.90,
            sevenDayUtilization: 0,
            localFiveHourTokens: 1_000_000,
            localSevenDayTokens: 0,
            accountId: account
        )
        #expect(LocalUsageEstimate.fiveHourLimit(for: account) == 0)
    }

    // MARK: - Per-account isolation

    @MainActor
    @Test func calibrate_isolatedPerAccount() {
        let accountA = Self.makeAccountId()
        let accountB = Self.makeAccountId()
        defer {
            Self.cleanup(accountA)
            Self.cleanup(accountB)
        }

        LocalUsageEstimate.calibrate(
            fiveHourUtilization: 0.50,
            sevenDayUtilization: 0.50,
            localFiveHourTokens: 1_000_000,
            localSevenDayTokens: 10_000_000,
            accountId: accountA
        )

        // Account A calibrated; account B untouched.
        #expect(LocalUsageEstimate.fiveHourLimit(for: accountA) == 2_000_000)
        #expect(LocalUsageEstimate.sevenDayLimit(for: accountA) == 20_000_000)
        #expect(LocalUsageEstimate.fiveHourLimit(for: accountB) == 0)
        #expect(LocalUsageEstimate.isCalibrated(for: accountA))
        #expect(!LocalUsageEstimate.isCalibrated(for: accountB))
        #expect(LocalUsageEstimate.calibratedAt(for: accountA) != nil)
        #expect(LocalUsageEstimate.calibratedAt(for: accountB) == nil)
    }

    @MainActor
    @Test func fiveHourPercent_usesOwnAccountsLimit() {
        let accountA = Self.makeAccountId()
        let accountB = Self.makeAccountId()
        defer {
            Self.cleanup(accountA)
            Self.cleanup(accountB)
        }

        LocalUsageEstimate.setFiveHourLimit(2_000_000, for: accountA)
        LocalUsageEstimate.setFiveHourLimit(10_000_000, for: accountB)

        // Same token count, different calibrated limits → different percentages.
        #expect(LocalUsageEstimate.fiveHourPercent(tokens: 1_000_000, accountId: accountA) == 50.0)
        #expect(LocalUsageEstimate.fiveHourPercent(tokens: 1_000_000, accountId: accountB) == 10.0)
    }

    // MARK: - Legacy global-key migration

    @MainActor
    @Test func migrateIfNeeded_movesGlobalValuesToActiveAccount() throws {
        let suiteName = "localEstimateMigration-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let account = Self.makeAccountId()
        defer { Self.cleanup(account) }

        // Pre-migration state: v2 version already current, global calibration present.
        defaults.set(2, forKey: "aibattery_calibration_version")
        defaults.set(3_000_000, forKey: "aibattery_calibrated_5h_limit")
        defaults.set(15_000_000, forKey: "aibattery_calibrated_7d_limit")

        LocalUsageEstimate.migrateIfNeeded(activeAccountId: account, defaults: defaults)

        // Values moved to the account-scoped keys; global keys cleared; flag set.
        #expect(defaults.integer(forKey: "aibattery_calibrated_5h_limit_\(account)") == 3_000_000)
        #expect(defaults.integer(forKey: "aibattery_calibrated_7d_limit_\(account)") == 15_000_000)
        #expect(defaults.object(forKey: "aibattery_calibrated_5h_limit") == nil)
        #expect(defaults.object(forKey: "aibattery_calibrated_7d_limit") == nil)
        #expect(defaults.bool(forKey: "aibattery_calibration_perAccount_migrated"))
    }

    @MainActor
    @Test func migrateIfNeeded_noActiveAccount_retriesNextLaunch() throws {
        let suiteName = "localEstimateMigration-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(2, forKey: "aibattery_calibration_version")
        defaults.set(3_000_000, forKey: "aibattery_calibrated_5h_limit")

        LocalUsageEstimate.migrateIfNeeded(activeAccountId: nil, defaults: defaults)

        // No account to attach the calibration to: keep the global value and
        // leave the flag unset so a later launch (with an account) migrates it.
        #expect(defaults.integer(forKey: "aibattery_calibrated_5h_limit") == 3_000_000)
        #expect(!defaults.bool(forKey: "aibattery_calibration_perAccount_migrated"))
    }

    @MainActor
    @Test func migrateIfNeeded_alreadyMigrated_noOp() throws {
        let suiteName = "localEstimateMigration-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let account = Self.makeAccountId()
        defer { Self.cleanup(account) }

        defaults.set(2, forKey: "aibattery_calibration_version")
        defaults.set(true, forKey: "aibattery_calibration_perAccount_migrated")
        defaults.set(3_000_000, forKey: "aibattery_calibrated_5h_limit")

        LocalUsageEstimate.migrateIfNeeded(activeAccountId: account, defaults: defaults)

        // Flag already set — a stray global value must not overwrite account state.
        #expect(defaults.object(forKey: "aibattery_calibrated_5h_limit_\(account)") == nil)
        #expect(defaults.integer(forKey: "aibattery_calibrated_5h_limit") == 3_000_000)
    }

    // MARK: - PlanTier per-account resolution (mixed tiers)

    @Test func planTier_billingType_mapsKnownValues() {
        #expect(PlanTier(billingType: "pro") == .pro)
        #expect(PlanTier(billingType: "Pro") == .pro)
        #expect(PlanTier(billingType: "max_5x") == .max5x)
        #expect(PlanTier(billingType: "max_20x") == .max20x)
        #expect(PlanTier(billingType: "team") == .team)
        #expect(PlanTier(billingType: "teams") == .team)
        #expect(PlanTier(billingType: "stripe_subscription") == nil)
        #expect(PlanTier(billingType: "") == nil)
    }

    @Test func planTier_effective_prefersAccountBillingType() throws {
        let suiteName = "planTierEffective-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Mixed-tier scenario: account A is max20x per its API-reported billing
        // type, account B has no billing info. The global user-selected tier
        // (whatever it is on this machine) must not override A's own tier.
        let records = [
            AccountRecord(id: "org-a", displayName: nil, billingType: "max_20x", addedAt: Date()),
            AccountRecord(id: "org-b", displayName: nil, billingType: nil, addedAt: Date()),
        ]
        let data = try JSONEncoder().encode(records)
        defaults.set(data, forKey: UserDefaultsKeys.accounts)

        #expect(PlanTier.effective(forAccountId: "org-a", defaults: defaults) == .max20x)
        // Account B falls back to the global selection (== PlanTier.current).
        #expect(PlanTier.effective(forAccountId: "org-b", defaults: defaults) == PlanTier.current)
        // Unknown account also falls back to the global selection.
        #expect(PlanTier.effective(forAccountId: "org-zzz", defaults: defaults) == PlanTier.current)
    }

    // MARK: - Helpers

    /// Unique per-test account ID — scoped keys make UserDefaults.standard safe
    /// to use without cross-test or cross-machine collisions.
    private static func makeAccountId() -> String {
        "estimate-test-\(UUID().uuidString)"
    }

    /// Remove the scoped keys a test created in UserDefaults.standard.
    @MainActor
    private static func cleanup(_ accountId: String) {
        let defaults = UserDefaults.standard
        for base in ["aibattery_calibrated_5h_limit", "aibattery_calibrated_7d_limit", "aibattery_calibrated_at"] {
            defaults.removeObject(forKey: "\(base)_\(accountId)")
        }
        LocalUsageEstimate.latestFiveHourTokens = 0
        LocalUsageEstimate.latestSevenDayTokens = 0
    }
}
