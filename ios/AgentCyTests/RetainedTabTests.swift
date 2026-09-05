import SwiftUI
import UIKit
import XCTest
@testable import AgentCy

@MainActor
final class RetainedTabTests: XCTestCase {
    func testUnvisitedTabsStayUnbuiltAndVisitedTabsKeepTheirState() async throws {
        let selection = TabSelection()
        var observations: [Int: [(UUID, Bool)]] = [:]
        let homeAppeared = expectation(description: "Home appears")
        let secondAppeared = expectation(description: "Second tab appears on selection")
        let homeReturned = expectation(description: "Home becomes active again")
        let content = TabHarness(selection: selection) { tab, identity, active in
            observations[tab, default: []].append((identity, active))
            if tab == 0, active {
                if observations[0]?.count == 1 {
                    homeAppeared.fulfill()
                } else {
                    homeReturned.fulfill()
                }
            } else if tab == 1, active {
                secondAppeared.fulfill()
            }
        }
        let host = UIHostingController(rootView: content)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }

        await fulfillment(of: [homeAppeared], timeout: 3)
        XCTAssertNil(observations[1], "An unvisited tab must not mount or start work")
        let originalIdentity = try XCTUnwrap(observations[0]?.first?.0)

        selection.index = 1
        await fulfillment(of: [secondAppeared], timeout: 3)
        XCTAssertEqual(observations[0]?.last?.1, false)

        selection.index = 0
        await fulfillment(of: [homeReturned], timeout: 3)
        XCTAssertEqual(observations[0]?.last?.0, originalIdentity, "Tab switching must preserve draft state")
        XCTAssertEqual(observations[1]?.last?.1, false, "Hidden work must receive the inactive signal")
    }
}

@MainActor
@Observable
private final class TabSelection {
    var index = 0
}

private struct TabHarness: View {
    let selection: TabSelection
    let observe: (Int, UUID, Bool) -> Void

    var body: some View {
        ZStack {
            RetainedTab(isSelected: selection.index == 0) {
                TabProbe { observe(0, $0, $1) }
            }
            RetainedTab(isSelected: selection.index == 1) {
                TabProbe { observe(1, $0, $1) }
            }
        }
    }
}

private struct TabProbe: View {
    let observe: (UUID, Bool) -> Void
    @State private var draftIdentity = UUID()
    @Environment(\.agentTabIsActive) private var active

    var body: some View {
        Text("Draft")
            .onChange(of: active, initial: true) { _, value in
                observe(draftIdentity, value)
            }
    }
}
