import Testing
@testable import AIBatteryCore

@Suite("APIProfile")
struct APIProfileTests {

    @Test func parse_bothHeaders() {
        let headers: [AnyHashable: Any] = [
            "anthropic-organization-id": "org-123",
            "x-organization-name": "Acme Corp",
        ]
        let profile = APIProfile.parse(headers: headers)
        #expect(profile != nil)
        #expect(profile?.organizationId == "org-123")
        #expect(profile?.organizationName == "Acme Corp")
    }

    @Test func parse_onlyOrgId() {
        let headers: [AnyHashable: Any] = [
            "anthropic-organization-id": "org-456",
        ]
        let profile = APIProfile.parse(headers: headers)
        #expect(profile != nil)
        #expect(profile?.organizationId == "org-456")
        #expect(profile?.organizationName == nil)
    }

    @Test func parse_onlyOrgName() {
        let headers: [AnyHashable: Any] = [
            "x-organization-name": "Test Org",
        ]
        let profile = APIProfile.parse(headers: headers)
        #expect(profile != nil)
        #expect(profile?.organizationId == nil)
        #expect(profile?.organizationName == "Test Org")
    }

    @Test func parse_noHeaders() {
        let profile = APIProfile.parse(headers: [:])
        #expect(profile == nil)
    }

    @Test func parse_irrelevantHeaders() {
        let headers: [AnyHashable: Any] = [
            "content-type": "application/json",
            "x-request-id": "abc",
        ]
        #expect(APIProfile.parse(headers: headers) == nil)
    }
}
