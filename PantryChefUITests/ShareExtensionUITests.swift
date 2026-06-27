import XCTest

/// End-to-end proof that the Share extension is real: drive Safari's actual system share
/// sheet and assert our "Save to PantryChef" action is offered for a web URL. That single
/// assertion exercises what unit tests can't — the OS wiring: the extension is registered,
/// embedded, and its activation rule fires for web URLs. Tapping it through and checking
/// the cross-process App-Group handoff is attempted too, but best-effort (share-sheet
/// automation is famously brittle); the deterministic guarantees live in
/// `SharedRecipeInboxTests`.
///
/// We share `example.com` on purpose: a featherweight page with no GDPR consent wall to
/// block the toolbar. The recipe content is irrelevant here — we're testing the *handoff*,
/// not the import.
final class ShareExtensionUITests: XCTestCase {

    private let shareURL = "https://example.com"
    private let actionLabel = "Save to PantryChef"

    override func setUpWithError() throws { continueAfterFailure = false }

    func testOurActionIsOfferedInSafariShareSheet() throws {
        // A just-installed appex isn't registered with PluginKit until the system has seen
        // its host app run — so launch PantryChef once first, or the share sheet assembles
        // before our extension exists and the test flakes.
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "host app didn't launch")
        app.terminate()

        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        safari.launch()
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 15), "Safari did not come up")

        openURL(shareURL, in: safari)
        dismissCoachmark(in: safari)
        openShareSheet(in: safari)

        // The key artifact: the assembled share grid. Attached regardless of outcome.
        attach(safari.screenshot(), name: "share-sheet")

        let action = findAction(in: safari)
        attach(safari.screenshot(), name: "after-reveal")
        XCTAssertTrue(action.exists,
                      "‘\(actionLabel)’ was not offered in the share sheet — the extension is not registered/activating. See attached screenshot.")

        // Best-effort: invoke it and confirm the relaunched app doesn't choke on the
        // drained import. Not a hard assertion (the cross-process write is covered by
        // SharedRecipeInboxTests); this is the belt-and-braces full-loop attempt.
        if action.exists {
            action.tap()
            let app = XCUIApplication()
            app.launch()
            _ = app.wait(for: .runningForeground, timeout: 10)
            attach(app.screenshot(), name: "app-after-share")
        }
    }

    // MARK: - Safari helpers

    private func openURL(_ url: String, in safari: XCUIApplication) {
        let pill = [safari.textFields["TabBarItemTitle"], safari.textFields["Address"], safari.textFields.firstMatch]
            .first { $0.waitForExistence(timeout: 8) }
        guard let bar = pill else { XCTFail("Safari address field not found"); return }
        // Tapping the collapsed pill swaps it for a different (expanded) editing field, so
        // the `bar` reference goes stale — type into the now-focused field via the app.
        bar.tap()
        XCTAssertTrue(safari.keyboards.firstMatch.waitForExistence(timeout: 6), "address-bar keyboard didn't appear")
        safari.typeText(url + "\n")
        // example.com renders this; confirms the page (and a shareable URL) is live.
        XCTAssertTrue(safari.webViews.staticTexts["Example Domain"].waitForExistence(timeout: 20),
                      "example.com did not load")
    }

    /// First-run Safari shows a “View Bookmarks, Share Menu, and Open Tabs” coachmark over
    /// the toolbar; close it so it can't swallow our taps.
    private func dismissCoachmark(in safari: XCUIApplication) {
        let close = safari.buttons["xmark.circle.fill"]
        if close.waitForExistence(timeout: 2) { close.tap() }
    }

    /// iOS 26 compact Safari has no standalone Share button — the sheet lives behind the
    /// “More” (•••) toolbar menu. Try a direct Share button first (older layouts), then the
    /// More-menu path.
    private func openShareSheet(in safari: XCUIApplication) {
        if tapIfPresent(safari.buttons["Share"], timeout: 2) { return }
        if tapIfPresent(safari.buttons["ShareButton"], timeout: 1) { return }
        // More menu → Share…
        guard tapIfPresent(safari.buttons["More"], timeout: 4) else {
            XCTFail("Could not find Safari’s Share or More button"); return
        }
        let shareItem = safari.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'Share'")).firstMatch
        _ = shareItem.waitForExistence(timeout: 4)
        shareItem.tap()
    }

    /// Our target in the share sheet. Note the apps row labels a share extension with its
    /// *parent app* name (“PantryChef”); the extension’s own display name (“Save to
    /// PantryChef”) only shows in the actions list. So match on “PantryChef” across element
    /// types, and if the apps row has demoted us behind “More”, open it first.
    private func findAction(in safari: XCUIApplication) -> XCUIElement {
        let pred = NSPredicate(format: "label CONTAINS[c] 'PantryChef'")
        func hit() -> XCUIElement? {
            for q in [safari.buttons, safari.cells, safari.staticTexts, safari.icons, safari.images] {
                let e = q.matching(pred).firstMatch
                if e.waitForExistence(timeout: 2) { return e }
            }
            return nil
        }
        if let direct = hit() { return direct }
        // The app row only promotes a few favourites — reveal the rest via its trailing
        // “More” (topmost of the sheet’s “More” buttons).
        let mores = safari.buttons.matching(identifier: "More")
        if mores.count > 0 {
            mores.element(boundBy: 0).tap()
            if let revealed = hit() { return revealed }
        }
        return safari.descendants(matching: .any).matching(pred).firstMatch
    }

    private func tapIfPresent(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        guard element.waitForExistence(timeout: timeout) else { return false }
        element.tap()
        return true
    }

    private func attach(_ shot: XCUIScreenshot, name: String) {
        let a = XCTAttachment(screenshot: shot)
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }
}
