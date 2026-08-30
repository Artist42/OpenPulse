import SwiftUI
import Charts

struct TemperatureView: View {
    @ObservedObject var db = AppDatabase.shared
    @State private var summary = TemperatureAnalyzer.Summary(baseline: nil, nights: [])
    @State private var daySamples: [HealthSample] = []

    var body: some View {
        NavigationStack {
            List {
                Section("Відхилення від базової лінії") {
                    if summary.nights.isEmpty {
                        Text("Замало нічних даних — потрібно щонайменше 5 ночей із температурою під час сну")
                            .foregroundStyle(.secondary)
                    } else {
                        Chart {
                            ForEach(summary.nights) { n in
                                BarMark(
                                    x: .value("Ніч", n.date, unit: .day),
                                    y: .value("Δ°C", n.deviation)
                                )
                                .foregroundStyle(n.deviation >= 0 ? .orange : .teal)
                            }
                            RuleMark(y: .value("Базова", 0))
                                .foregroundStyle(.secondary)
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                        }
                        .frame(height: 190)
                        .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                        row("Останнє відхилення", summary.lastDeviation.map { String(format: "%+.2f °C", $0) } ?? "—")
                        row("Базова лінія", summary.baseline.map { String(format: "%.2f °C", $0) } ?? "—")
                        row("Ночей у вибірці", "\(summary.nights.count)")
                    }
                }

                Section("Сирий сенсор за 24 години") {
                    if rawPoints.isEmpty {
                        Text("Немає даних за останню добу").foregroundStyle(.secondary)
                    } else {
                        Chart(rawPoints) { p in
                            LineMark(x: .value("Час", p.date), y: .value("°C", p.value))
                                .foregroundStyle(.orange)
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .frame(height: 150)
                        .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                    }
                    Text("Це внутрішній сенсор годинника: абсолютні значення нижчі за температуру тіла й залежать від середовища. Показові лише тренди та відхилення від власної базової лінії.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Температура")
            .onAppear { reload() }
            .onChange(of: db.sampleCount) { _, _ in reload() }
        }
    }

    private var rawPoints: [HeartRatePoint] {
        daySamples.compactMap { s in
            guard let t = s.temperature, s.activity != "NOT_WORN" else { return nil }
            return HeartRatePoint(date: Date(timeIntervalSince1970: TimeInterval(s.ts)), value: t)
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack { Text(title); Spacer(); Text(value).bold() }
    }

    private func reload() {
        let now = Date().addingTimeInterval(600)
        let from = Calendar.current.startOfDay(for: Date()).addingTimeInterval(-32 * 86400)
        let samples = db.samples(from: from, to: now)
        let nights = SleepIntervalBuilder.nights(from: samples)
        summary = TemperatureAnalyzer.summary(samples: samples, nights: nights)
        daySamples = db.samples(from: now.addingTimeInterval(-24 * 3600), to: now)
    }
}
