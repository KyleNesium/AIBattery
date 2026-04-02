import Testing
@testable import AIBatteryCore

@Suite("APIProfile")
struct APIProfileTests {

    @Test func parse_withOrgId() {
        let headers: [AnyHashable: Any] = [
            "anthropic-organization-id": "org-123",
            "x-organization-name": "Acme Corp",
        ]
        let profile = APIProfile.parse(headers: headers)
        #expect(profile != nil)
        #expect(profile?.organizationId == "org-123")
        #expect(profile?.workspaceId == nil)
    }

    @Test func parse_onlyOrgId() {
        let headers: [AnyHashable: Any] = [
            "anthropic-organization-id": "org-456",
        ]
        let profile = APIProfile.parse(headers: headers)
        #expect(profile != nil)
        #expect(profile?.organizationId == "org-456")
    }

    @Test func parse_mixedCaseOrgIdHeader() {
        let headers: [AnyHashable: Any] = [
            "Anthropic-Organization-Id": "org-789",
        ]
        let profile = APIProfile.parse(headers: headers)
        #expect(profile != nil)
        #expect(profile?.organizationId == "org-789")
    }

    @Test func parse_onlyOrgName_returnsNil() {
        let headers: [AnyHashable: Any] = [
            "x-organization-name": "Test Org",
        ]
        let profile = APIProfile.parse(headers: headers)
        #expect(profile == nil)
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

    @Test func parse_empty_returnsNil() {
        let headers: [AnyHashable: Any] = [
            "anthropic-organization-id": "",
        ]
        #expect(APIProfile.parse(headers: headers) == nil)
    }

    @Test func parse_tooLong_returnsNil() {
        let headers: [AnyHashable: Any] = [
            "anthropic-organization-id": String(repeating: "a", count: 129),
        ]
        #expect(APIProfile.parse(headers: headers) == nil)
    }

    @Test func parse_specialChars_returnsNil() {
        let headers: [AnyHashable: Any] = [
            "anthropic-organization-id": "org/123;DROP TABLE",
        ]
        #expect(APIProfile.parse(headers: headers) == nil)
    }

    @Test func parse_validWithHyphensUnderscores() {
        let headers: [AnyHashable: Any] = [
            "anthropic-organization-id": "my-org_123",
        ]
        let profile = APIProfile.parse(headers: headers)
        #expect(profile != nil)
        #expect(profile?.organizationId == "my-org_123")
    }

    @Test func parse_workspaceHeaders() {
        let headers: [AnyHashable: Any] = [
            "anthropic-workspace-id": "ws_123",
            "anthropic-workspace-name": "Product Eng",
        ]
        let profile = APIProfile.parse(headers: headers)
        #expect(profile != nil)
        #expect(profile?.organizationId == nil)
        #expect(profile?.workspaceId == "ws_123")
        #expect(profile?.workspaceName == "Product Eng")
    }

    @Test func parse_clientData_withWorkspaceAndOrg() throws {
        let data = try #require("""
        {
          "organization": { "id": "org_abc" },
          "workspace": { "id": "ws_123", "name": "Platform" }
        }
        """.data(using: .utf8))
        let profile = APIProfile.parse(clientData: data)
        #expect(profile != nil)
        #expect(profile?.organizationId == "org_abc")
        #expect(profile?.workspaceId == "ws_123")
        #expect(profile?.workspaceName == "Platform")
    }
}
