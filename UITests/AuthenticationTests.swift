/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import EarlGrey

class AuthenticationTests: KIFTestCase {
    private var webRoot: String!

    override func setUp() {
        super.setUp()
        webRoot = SimplePageServer.start()
        
        EarlGrey().selectElementWithMatcher(grey_allOfMatchers(
            grey_accessibilityID("IntroViewController.startBrowsingButton"), grey_sufficientlyVisible()))
            .performAction(grey_tap())
    }
    
    override func tearDown() {
        super.tearDown()
    }

    /**
     * Tests HTTP authentication credentials and auto-fill.
     */
    func testAuthentication() {
        loadAuthPage()

        // Make sure that 3 invalid credentials result in authentication failure.
        enterCredentials(usernameValue: "Username", passwordValue: "Password", username: "foo", password: "bar")
        enterCredentials(usernameValue: "foo", passwordValue: "•••", username: "foo2", password: "bar2")
        enterCredentials(usernameValue: "foo2", passwordValue: "••••", username: "foo3", password: "bar3")
        
        // Use KIFTest framework for checking elements within webView
        tester().waitForWebViewElementWithAccessibilityLabel("auth fail")

        // Enter valid credentials and ensure the page loads.
        EarlGrey().selectElementWithMatcher(grey_accessibilityLabel("Reload")).performAction(grey_tap())
        enterCredentials(usernameValue: "Username", passwordValue: "Password", username: "user", password: "pass")
        tester().waitForWebViewElementWithAccessibilityLabel("logged in")

        // Save the credentials.
        EarlGrey().selectElementWithMatcher(grey_accessibilityLabel("Save Login"))
            .inRoot(grey_kindOfClass(NSClassFromString("Client.SnackButton")))
            .performAction(grey_tap())
        
        logOut()
        loadAuthPage()

        // Make sure the credentials were saved and auto-filled.
        EarlGrey().selectElementWithMatcher(grey_accessibilityLabel("Log in"))
            .inRoot(grey_kindOfClass(NSClassFromString("_UIAlertControllerActionView")))
            .performAction(grey_tap())
        tester().waitForWebViewElementWithAccessibilityLabel("logged in")

        // Add a private tab.
        EarlGrey().selectElementWithMatcher(grey_accessibilityLabel("Menu")).performAction(grey_tap())
        EarlGrey().selectElementWithMatcher(grey_accessibilityLabel("New Private Tab"))
            .inRoot(grey_kindOfClass(NSClassFromString("Client.MenuItemCollectionViewCell")))
            .performAction(grey_tap())
        loadAuthPage()

        // Make sure the auth prompt is shown.
        // Note that in the future, we might decide to auto-fill authentication credentials in private browsing mode,
        // but that's not currently supported. We assume the username and password fields are empty.
        enterCredentials(usernameValue: "Username", passwordValue: "Password", username: "user", password: "pass")
        tester().waitForWebViewElementWithAccessibilityLabel("logged in")

    }

    private func loadAuthPage() {
        EarlGrey().selectElementWithMatcher(grey_accessibilityID("url")).performAction(grey_tap())
        EarlGrey().selectElementWithMatcher(grey_accessibilityID("address")).performAction(grey_typeText("\(webRoot)/auth.html\n"))
    }

    private func logOut() {
        EarlGrey().selectElementWithMatcher(grey_accessibilityID("url")).performAction(grey_tap())
        EarlGrey().selectElementWithMatcher(grey_accessibilityID("address")).performAction(grey_typeText("\(webRoot)/auth.html?logout=1\n"))
        EarlGrey().selectElementWithMatcher(grey_accessibilityLabel("Cancel"))
            .inRoot(grey_kindOfClass(NSClassFromString("_UIAlertControllerActionView")))
            .performAction(grey_tap())
    }

    private func enterCredentials(usernameValue usernameValue: String, passwordValue: String, username: String, password: String) {
        let usernameField = EarlGrey().selectElementWithMatcher(grey_accessibilityValue(usernameValue))
        let passwordField = EarlGrey().selectElementWithMatcher(grey_accessibilityValue(passwordValue))
        
        if (usernameValue != "Username") {
            usernameField.performAction(grey_doubleTap())
            EarlGrey().selectElementWithMatcher(grey_accessibilityLabel("Select All"))
                .inRoot(grey_kindOfClass(NSClassFromString("UICalloutBarButton")))
                .performAction(grey_tap())
        }
        
        usernameField.performAction(grey_typeText(username))
        passwordField.performAction(grey_typeText(password))
        
        EarlGrey().selectElementWithMatcher(grey_accessibilityLabel("Log in"))
            .inRoot(grey_kindOfClass(NSClassFromString("_UIAlertControllerActionView")))
            .performAction(grey_tap())    }
}
