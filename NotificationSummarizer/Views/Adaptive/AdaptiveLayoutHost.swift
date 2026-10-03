import SwiftUI

/// Measures the available width once and publishes the resolved layout to the
/// whole subtree.
///
/// Sizing decisions are made in exactly one place. Views read
/// `@Environment(\.resolvedLayout)` instead of re-deriving a profile from size
/// classes, which is what previously let the sidebar, the grid and the detail
/// column each disagree about how many columns fit.
struct AdaptiveLayoutHost<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let idiom: DeviceIdiom
    @ViewBuilder private let content: (ResolvedLayout) -> Content

    init(
        idiom: DeviceIdiom = DeviceIdiom(UIDevice.current.userInterfaceIdiom),
        @ViewBuilder content: @escaping (ResolvedLayout) -> Content
    ) {
        self.idiom = idiom
        self.content = content
    }

    var body: some View {
        GeometryReader { proxy in
            content(
                .resolve(
                    width: proxy.size.width,
                    horizontalSizeClass: horizontalSizeClass,
                    verticalSizeClass: verticalSizeClass,
                    idiom: idiom,
                    dynamicTypeSize: dynamicTypeSize
                )
            )
        }
    }
}
