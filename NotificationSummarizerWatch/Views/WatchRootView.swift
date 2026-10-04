import SwiftUI

/// Root of the watch app.
///
/// watchOS is a three-glance surface, so the whole app is a vertical-page `TabView`:
/// each page answers exactly one question -- what is new (Feed), what does this text
/// mean (Capture), and how am I doing (Overview) -- instead of compressing the phone's
/// dashboard into a narrower column.
///
/// `.verticalPage` also gives the Digital Crown something to page through, which is
/// the gesture people reach for first on this screen size.
///
/// **Constraint this imposes:** no page may attach a `.toolbar`. On watchOS a
/// `ToolbarItem` inside a vertical-page `TabView` collapses that page to zero size --
/// the app launches, the page dots appear, and the screen stays black. Every action
/// that would naturally live in a toolbar (the feed's category filter, capture's
/// template picker, detail's read/delete) is therefore a control in the page content.
struct WatchRootView: View {
    @State private var selection: WatchRootPage = .feed

    var body: some View {
        TabView(selection: $selection) {
            WatchFeedView()
                .tabItem {
                    Label("Feed", systemImage: "bell.fill")
                }
                .tag(WatchRootPage.feed)

            WatchQuickCaptureView()
                .tabItem {
                    Label("Capture", systemImage: "text.viewfinder")
                }
                .tag(WatchRootPage.capture)

            WatchOverviewView()
                .tabItem {
                    Label("Overview", systemImage: "chart.bar.fill")
                }
                .tag(WatchRootPage.overview)
        }
        .tabViewStyle(.verticalPage)
    }
}

/// Identity of a vertical page. `Hashable` because `TabView(selection:)` needs it.
private enum WatchRootPage: Hashable {
    case feed
    case capture
    case overview
}

// MARK: - Previews

#Preview("Root") {
    WatchRootView()
}
