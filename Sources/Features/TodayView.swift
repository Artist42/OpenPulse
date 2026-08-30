import SwiftUI
import Charts

struct TodayView: View {
    @EnvironmentObject var ble: BLEManager
    @ObservedObject var db = AppDatabase.shared
    @ObservedObject var sync = SyncEngine.shared

    @State private var todaySamples: [HealthSample] = []
    @State private var lastHR: HeartRatePoint?
    @State private var lastNight: SleepNight?
    @State private var tempSummary = TemperatureAnalyzer.Summary(baseline: nil, nights: [])
    @State private var todayNaps: [SleepNap] = []

    var body: some View {
        NavigationStack {
            List {
                Section("Зараз") {
                    row("Пульс", lastHR.map { "\(Int($0.value.rounded())) уд/хв" } ?? "—",
                        detail: lastHR.map { $0.date.formatted(date: .omitted, time: .shortened) })
                        row("Кроки сьогодні", "\(todaySteps)")
                        row("Сон минулої ночі",
                            lastNight.map { SleepFormat.duration($0.asleepDuration) } ?? "—",
                            detail: lastNight.map { "глибокий \(SleepFormat.duration($0.deepDuration))" })
                        row("Дрімота сьогодні",
                            todayNaps.isEmpty ? "—" : SleepFormat.duration(todayNaps.reduce(0) { $0 + $1.duration }),
                            detail: todayNaps.isEmpty ? nil : "епізодів: \(todayNaps.count)")
                    row("Температура", lastTemperature.map { String(format: "%.1f°", $0) } ?? "—",
                        detail: tempSummary.lastDeviation.map { String(format: "%+.2f° до базової", $0) })
                    row("Батарея годинника", lastBattery.map { "\(Int($0))%" } ?? "—")
                }

                Section("Пульс сьогодні") {
                    if hrPoints.isEmpty {
                        Text("Ще немає даних за сьогодні").foregroundStyle(.secondary)
                    } else {
                        Chart(hrPoints) { p in
                            LineMark(
                                x: .value("Час", p.date),
                                y: .value("Пульс", p.value)
                            )
                            .foregroundStyle(.red)
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .frame(height: 160)
                        .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                    }
                }

                Section("Годинник") {
                    HStack {
                        Circle()
                            .fill(ble.isConnected ? Color.green : Color.red)
                            .frame(width: 10, height: 10)
                        Text(ble.statusText)
                    }
                }

                Section("Синхронізація") {
                    Text(sync.statusText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button {
                        sync.startSync()
                    } label: {
                        if sync.isSyncing {
                            ProgressView()
                        } else {
                            Text("Синхронізувати зараз")
                        }
                    }
                    .disabled(sync.isSyncing || !ble.isConnected)

                    Button("Повний ресинк (з нуля)", role: .destructive) {
                        sync.resetCursor()
                        sync.startSync()
                    }
                    .disabled(sync.isSyncing || !ble.isConnected)
                }
            }
            .navigationTitle("Сьогодні")
            .onAppear { reload() }
            .onChange(of: db.sampleCount) { _, _ in reload() }
        }
    }

    private var todaySteps: Int { todaySamples.compactMap(\.steps).reduce(0, +) }
    private var lastTemperature: Double? { todaySamples.compactMap(\.temperature).last }
    private var lastBattery: Double? { todaySamples.compactMap(\.battery).last }
    private var hrPoints: [HeartRatePoint] {
        todaySamples.compactMap { s in
            guard let hr = s.hr else { return nil }
            return HeartRatePoint(date: Date(timeIntervalSince1970: TimeInterval(s.ts)), value: hr)
        }
    }

    private func row(_ title: String, _ value: String, detail: String? = nil) -> some View {
        HStack {
            Text(title)
            Spacer()
            if let detail {
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
            Text(value).bold()
        }
    }

    private func reload() {
        let start = Calendar.current.startOfDay(for: Date())
        todaySamples = db.samples(from: start, to: Date().addingTimeInterval(600))
        lastHR = db.latestHeartRate()
        let sleepFrom = start.addingTimeInterval(-36 * 3600)
        let sleepSamples = db.samples(from: sleepFrom, to: Date().addingTimeInterval(600))
        let monthFrom = start.addingTimeInterval(-32 * 86400)
        let monthSamples = db.samples(from: monthFrom, to: Date().addingTimeInterval(600))
        let sleepResult = SleepIntervalBuilder.analyze(from: monthSamples)
        lastNight = sleepResult.nights.last
        todayNaps = sleepResult.naps.filter { $0.start >= start }
        tempSummary = TemperatureAnalyzer.summary(samples: monthSamples, nights: sleepResult.nights)
    }
}
