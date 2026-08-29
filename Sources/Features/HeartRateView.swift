import SwiftUI
import Charts

struct HeartRateView: View {
    enum Period: String, CaseIterable, Identifiable {
        case day = "День"
        case week = "Тиждень"
        case month = "Місяць"
        var id: String { rawValue }
        var days: Int {
            switch self {
            case .day: return 1
            case .week: return 7
            case .month: return 30
            }
        }
    }

    struct RangePoint: Identifiable {
        let date: Date
        let value: Double
        let minValue: Double
        let maxValue: Double
        var id: Date { date }
    }

    @ObservedObject var db = AppDatabase.shared
    @State private var period: Period = .day
    @State private var samples: [HealthSample] = []

    var body: some View {
        NavigationStack {
            List {
                Section("Графік") {
                    Picker("Період", selection: $period) {
                        ForEach(Period.allCases) { p in Text(p.rawValue).tag(p) }
                    }
                    .pickerStyle(.segmented)

                    if chartPoints.isEmpty {
                        Text("Немає даних за цей період").foregroundStyle(.secondary)
                    } else {
                        Chart(chartPoints) { p in
                            if period != .day {
                                AreaMark(
                                    x: .value("Час", p.date),
                                    yStart: .value("Мін", p.minValue),
                                    yEnd: .value("Макс", p.maxValue)
                                )
                                .foregroundStyle(Color.red.opacity(0.15))
                            }
                            LineMark(
                                x: .value("Час", p.date),
                                y: .value("Пульс", p.value)
                            )
                            .foregroundStyle(.red)
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .frame(height: 220)
                        .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                    }
                }

                Section("Показники") {
                    statRow("Мінімум", minHR)
                    statRow("Середній", avgHR)
                    statRow("Максимум", maxHR)
                    statRow("У спокої (орієнтовно)", restingHR)
                }
            }
            .navigationTitle("Пульс")
            .onAppear { reload() }
            .onChange(of: period) { _, _ in reload() }
            .onChange(of: db.sampleCount) { _, _ in reload() }
        }
    }

    private var chartPoints: [RangePoint] {
        let hrSamples = samples.filter { $0.hr != nil }
        guard !hrSamples.isEmpty else { return [] }
        if period == .day {
            return hrSamples.map { s in
                let hr = s.hr ?? 0
                return RangePoint(date: Date(timeIntervalSince1970: TimeInterval(s.ts)), value: hr, minValue: hr, maxValue: hr)
            }
        }
        let bucket: Double = period == .week ? 3600 : 6 * 3600
        let grouped = Dictionary(grouping: hrSamples) { s in
            floor(Double(s.ts) / bucket) * bucket
        }
        return grouped.map { key, group in
            let hrs = group.compactMap(\.hr)
            return RangePoint(
                date: Date(timeIntervalSince1970: key + bucket / 2),
                value: hrs.reduce(0, +) / Double(hrs.count),
                minValue: hrs.min() ?? 0,
                maxValue: hrs.max() ?? 0
            )
        }
        .sorted { $0.date < $1.date }
    }

    private var allHRs: [Double] { samples.compactMap(\.hr) }
    private var minHR: Double? { allHRs.min() }
    private var maxHR: Double? { allHRs.max() }
    private var avgHR: Double? { allHRs.isEmpty ? nil : allHRs.reduce(0, +) / Double(allHRs.count) }
    private var restingHR: Double? {
        guard !allHRs.isEmpty else { return nil }
        let sorted = allHRs.sorted()
        let n = max(1, sorted.count / 10)
        return sorted.prefix(n).reduce(0, +) / Double(n)
    }

    private func statRow(_ title: String, _ value: Double?) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value.map { "\(Int($0.rounded())) уд/хв" } ?? "—").bold()
        }
    }

    private func reload() {
        let to = Date().addingTimeInterval(600)
        let from = Calendar.current.startOfDay(for: Date().addingTimeInterval(TimeInterval(-(period.days - 1) * 86400)))
        samples = db.samples(from: from, to: to)
    }
}
