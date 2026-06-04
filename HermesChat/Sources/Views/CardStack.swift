import SwiftUI

// MARK: - CardStack

/// A rolodex-style stack that lets users swipe or programmatically
/// cycle between multiple views (e.g. local vs server input bars).
/// Adapted from HuggingChat macOS.
struct CardStack<Content: View>: View {

    private let views: [Content]
    @State private var dragProgress = 0.0
    @State private var containerSize = CGSize.zero
    @Binding var selectedIndex: Int
    @State private var isAnimating = false

    init(_ views: [Content], selectedIndex: Binding<Int>) {
        self.views = views
        self._selectedIndex = selectedIndex
    }

    var body: some View {
        ZStack {
            ForEach(0..<views.count, id: \.self) { index in
                views[index]
                    .zIndex(zIndex(for: index))
                    .offset(y: yOffset(for: index))
                    .scaleEffect(scale(for: index), anchor: .center)
            }
        }
        .measure($containerSize)
        .gesture(dragGesture)
    }

    // MARK: - Gesture

    var dragGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                guard !isAnimating else { return }
                self.dragProgress = -(value.translation.height / containerSize.height)
            }
            .onEnded { _ in
                snapToNearestIndex()
            }
    }

    // MARK: - Programmatic Switch

    func simulateDrag() {
        guard !isAnimating else { return }
        isAnimating = true
        let isLastCard = selectedIndex == views.count - 1
        withAnimation(.easeInOut(duration: 0.3)) {
            self.dragProgress = isLastCard ? -0.4 : 0.4
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            snapToNearestIndex()
            isAnimating = false
        }
    }

    // MARK: - Snapping

    func snapToNearestIndex() {
        let threshold = 0.3
        if abs(dragProgress) < threshold {
            withAnimation(.bouncy) {
                self.dragProgress = 0.0
            }
        } else {
            let direction = dragProgress < 0 ? -1 : 1
            withAnimation(.smooth(duration: 0.25)) {
                go(to: selectedIndex + direction)
            }
        }
    }

    func go(to index: Int) {
        let maxIndex = views.count - 1
        if index > maxIndex {
            self.selectedIndex = maxIndex
        } else if index < 0 {
            self.selectedIndex = 0
        } else {
            self.selectedIndex = index
        }
        self.dragProgress = 0
    }

    // MARK: - Computed Positions

    var progressIndex: Double {
        dragProgress + Double(selectedIndex)
    }

    func currentPosition(for index: Int) -> Double {
        progressIndex - Double(index)
    }

    func zIndex(for index: Int) -> Double {
        let position = currentPosition(for: index)
        return -abs(position)
    }

    func yOffset(for index: Int) -> Double {
        guard containerSize.height > 0 else { return 0 }
        let padding = containerSize.height / 10
        let y = (Double(index) - progressIndex) * padding
        let maxIndex = views.count - 1
        if index == selectedIndex && progressIndex < Double(maxIndex) && progressIndex > 0 {
            return y * swingOutMultiplier
        }
        return y
    }

    var swingOutMultiplier: Double {
        abs(sin(Double.pi * progressIndex) * 25)
    }

    func scale(for index: Int) -> CGFloat {
        return 1.0 - (0.3 * abs(currentPosition(for: index)))
    }
}

// MARK: - Measure Helper

extension View {
    /// Measures the geometry of the attached view.
    func measure(_ size: Binding<CGSize>) -> some View {
        self.background {
            GeometryReader { reader in
                Color.clear.preference(
                    key: ViewSizePreferenceKey.self,
                    value: reader.size
                )
            }
        }
        .onPreferenceChange(ViewSizePreferenceKey.self) {
            size.wrappedValue = $0 ?? .zero
        }
    }
}

struct ViewSizePreferenceKey: PreferenceKey {
    static func reduce(value: inout CGSize?, nextValue: () -> CGSize?) {
        value = nextValue() ?? value
    }
    static nonisolated(unsafe) var defaultValue: CGSize? = nil
}