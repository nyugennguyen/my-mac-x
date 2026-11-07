import XCTest
@testable import MyMacX

final class AppRulePolicyTests: XCTestCase {
    func testDefaultPolicyIncludesIdentifiedAppsAndFailsClosedWithoutAValidIdentifier() {
        let policy = AppRulePolicy()

        XCTAssertEqual(policy.decision(for: "com.example.Editor"), .included)
        XCTAssertEqual(policy.decision(for: nil), .excluded)
        XCTAssertEqual(policy.decision(for: "Quarterly plan"), .excluded)
    }

    func testRulesMatchBundleIdentifiersCaseInsensitively() throws {
        let editorID = try XCTUnwrap(ApplicationBundleIdentifier("com.example.Editor"))
        let policy = AppRulePolicy(
            rules: [AppRule(bundleIdentifier: editorID, decision: .excluded)]
        )

        XCTAssertEqual(policy.decision(for: "COM.EXAMPLE.EDITOR"), .excluded)
        XCTAssertEqual(policy.decision(for: "com.example.Browser"), .included)
    }

    func testExplicitIncludeOverridesExcludeUnmatchedAndConflictFailsClosed() throws {
        let editorID = try XCTUnwrap(ApplicationBundleIdentifier("com.example.Editor"))
        let policy = AppRulePolicy(
            unmatched: .excluded,
            rules: [
                AppRule(bundleIdentifier: editorID, decision: .included),
                AppRule(bundleIdentifier: editorID, decision: .excluded),
            ]
        )

        XCTAssertEqual(policy.decision(for: "com.example.Editor"), .excluded)
        XCTAssertEqual(policy.decision(for: "com.example.Browser"), .excluded)
    }

    func testRuntimeReplacementTakesEffectWithoutRestart() async throws {
        let editorID = try XCTUnwrap(ApplicationBundleIdentifier("com.example.Editor"))
        let runtime = AppRuleRuntime()

        let before = await runtime.decision(for: "com.example.Editor")
        await runtime.replace(
            with: AppRulePolicy(
                rules: [AppRule(bundleIdentifier: editorID, decision: .excluded)]
            )
        )
        let after = await runtime.decision(for: "com.example.Editor")

        XCTAssertEqual(before, .included)
        XCTAssertEqual(after, .excluded)
    }

    func testBundleIdentifierRoundTripsInCanonicalFormAndRejectsContent() throws {
        let identifier = try XCTUnwrap(ApplicationBundleIdentifier("COM.Example.Editor"))

        let data = try JSONEncoder().encode(identifier)
        let decoded = try JSONDecoder().decode(ApplicationBundleIdentifier.self, from: data)

        XCTAssertEqual(decoded.value, "com.example.editor")
        XCTAssertNil(ApplicationBundleIdentifier("Document title"))
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                ApplicationBundleIdentifier.self,
                from: Data(#""Document title""#.utf8)
            )
        )
    }

    func testAppRuleMatchingAndFailClosedDefaultSemantics() throws {
        let terminalID = try XCTUnwrap(ApplicationBundleIdentifier("com.apple.Terminal"))
        let steamID = try XCTUnwrap(ApplicationBundleIdentifier("com.valvesoftware.steam"))

        let policy = AppRulePolicy(
            unmatched: .included,
            rules: [
                AppRule(bundleIdentifier: terminalID, decision: .included),
                AppRule(bundleIdentifier: steamID, decision: .excluded)
            ]
        )

        // Matching
        XCTAssertEqual(policy.decision(for: "com.apple.Terminal"), .included)
        XCTAssertEqual(policy.decision(for: "com.valvesoftware.steam"), .excluded)
        XCTAssertEqual(policy.decision(for: "COM.VALVESOFTWARE.STEAM"), .excluded)
        XCTAssertEqual(policy.decision(for: "com.apple.Safari"), .included) // unmatched default

        // Fail-closed semantics: malformed or nil ALWAYS fails closed (excluded)
        XCTAssertEqual(policy.decision(for: nil), .excluded)
        XCTAssertEqual(policy.decision(for: ""), .excluded)
        XCTAssertEqual(policy.decision(for: "invalid bundle"), .excluded)
        XCTAssertEqual(policy.decision(for: "missing-dot"), .excluded)
    }

    func testBundleIdentifierValidationSurfacesFailClosedHonesty() {
        XCTAssertTrue(ApplicationBundleIdentifier.isValid("com.apple.Terminal"))
        XCTAssertTrue(ApplicationBundleIdentifier.isValid("com.valvesoftware.steam"))
        XCTAssertFalse(ApplicationBundleIdentifier.isValid(""))
        XCTAssertFalse(ApplicationBundleIdentifier.isValid("invalid"))
        XCTAssertFalse(ApplicationBundleIdentifier.isValid("com. apple.invalid"))

        // Explanatory fail-closed feedback for UI
        XCTAssertEqual(
            ApplicationBundleIdentifier.validationError(for: ""),
            "Bundle identifier cannot be empty."
        )
        XCTAssertEqual(
            ApplicationBundleIdentifier.validationError(for: "Terminal"),
            "Invalid bundle identifier. Missing or malformed identities fail closed and are excluded."
        )
        XCTAssertNil(ApplicationBundleIdentifier.validationError(for: "com.apple.Terminal"))
    }
}
