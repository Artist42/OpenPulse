import SwiftUI
import Charts

// Спільний модифікатор для графіків: горизонтальний скрол +
// масштабування двома пальцями (розвести — детальніше, звести — ширше).
struct ChartZoom: ViewModifier {
    @Binding var visibleSeconds: Double
    let minSeconds: Double
    let maxSeconds: Double
    @State private var baseSeconds: Double?

    func body(content: Content) -> some View {
        content
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: visibleSeconds)
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { scale in
                        let base = baseSeconds ?? visibleSeconds
                        if baseSeconds == nil { baseSeconds = base }
                        visibleSeconds = min(max(base / Double(scale), minSeconds), maxSeconds)
                    }
                    .onEnded { _ in baseSeconds = nil }
            )
    }
}

extension View {
    func zoomableChart(visibleSeconds: Binding<Double>, minSeconds: Double, maxSeconds: Double) -> some View {
        modifier(ChartZoom(visibleSeconds: visibleSeconds, minSeconds: minSeconds, maxSeconds: maxSeconds))
    }
}
