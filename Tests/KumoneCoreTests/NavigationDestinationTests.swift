import AppKit
import SwiftUI
import Testing
@testable import KumoneCore

@Suite("Navigation destination tests")
struct NavigationDestinationTests {
    @Test func doesNotAppendTheCurrentDestination() {
        var destinations: [Destination] = [.artist(42)]

        destinations.appendIfNotCurrent(.artist(42))

        #expect(destinations == [.artist(42)])
    }

    @Test func appendsADifferentDestination() {
        var destinations: [Destination] = [.album(7)]

        destinations.appendIfNotCurrent(.artist(42))

        #expect(destinations == [.album(7), .artist(42)])
    }

    @Test func menuPagesCanBePinnedAndUnpinnedInOrder() {
        var pages: [RootPage] = []
        RootPage.saved.togglePin(in: &pages)
        RootPage.explore.togglePin(in: &pages)
        #expect(pages == [.saved, .explore])
        #expect(pages.map(\.rawValue).compactMap(RootPage.init(rawValue:)) == pages)

        RootPage.saved.togglePin(in: &pages)
        #expect(pages == [.explore])
        RootPage.saved.togglePin(in: &pages)
        #expect(pages == [.explore, .saved])
    }

    @Test func primaryTabsCannotBeDuplicatedByPinning() {
        var pages: [RootPage] = []
        for page in RootPage.primaryPages {
            page.togglePin(in: &pages)
        }
        #expect(pages.isEmpty)
        #expect(RootPage.menuPages.contains(.saved))
        #expect(!RootPage.menuPages.contains(.created))
    }

    @Test func navigationContentFitsItsReservedSpace() {
        for width in [420.0, 650, 790, 1024, 1200] {
            for tabsWidth in [206.0, 2000] {
                for searchExpanded in [false, true] {
                    let layout = NavigationBarLayout(windowWidth: width, tabsWidth: tabsWidth,
                                                     searchExpanded: searchExpanded)
                    #expect(layout.tabsWidth > 0)
                    #expect(layout.searchWidth > 24)
                    let searchReservation = searchExpanded ? layout.searchWidth : 24
                    #expect(layout.tabsWidth + 2 * (searchReservation + 18) <= layout.width + 0.001)
                }
            }
        }

        // Extra pinned tabs fit at the usual window width while search is closed.
        let pinnedTabs = NavigationBarLayout(windowWidth: 790, tabsWidth: 350)
        #expect(pinnedTabs.tabsWidth == 350)
        let searching = NavigationBarLayout(windowWidth: 790, tabsWidth: 350, searchExpanded: true)
        #expect(searching.tabsWidth < pinnedTabs.tabsWidth)
    }

    @Test @MainActor func titlebarAttachmentResizesWithoutCreatingToolbarItems() {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .unifiedCompact
        window.toolbar = NSToolbar(identifier: "navigation-layout-test")
        defer { window.close() }
        let titlebar = MainWindowTitlebar()

        for width in [1200.0, 1024, 790, 650, 420, 790, 1200] {
            window.setContentSize(NSSize(width: width, height: 600))
            titlebar.update(content: AnyView(Color.clear), in: window)
            window.layoutIfNeeded()
            #expect(abs(titlebar.view.frame.width - (width - MainWindowTitlebar.leadingInset))
                <= 0.5 / window.backingScaleFactor)
            #expect(window.titlebarAccessoryViewControllers.count == 1)
            #expect(window.toolbar?.items.isEmpty == true)
        }

        titlebar.setFadedOut(true)
        // Immersive controls need the accessory's container removed from
        // hit testing, not just an invisible hosting view.
        #expect(window.titlebarAccessoryViewControllers.isEmpty)
        titlebar.setFadedOut(false)
        #expect(window.titlebarAccessoryViewControllers.count == 1)
        #expect(window.titlebarAccessoryViewControllers.first === titlebar)
    }
}
