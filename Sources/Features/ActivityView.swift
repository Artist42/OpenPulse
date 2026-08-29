import SwiftUI
import Charts

struct ActivityView: View {
    enum Period: String, CaseIterable, Identifiable {
        case week = "Тиждень"
        case month = "Місяць"
        var id: String { rawValue }
        var days: Int { self == .week ? 7 : 30 }
    }

    @ObservedObject var db = AppDatabase.shared
    @State private var period: Period = .week
    @State private var periodSamples: [HealthSample] = []
    @State private var todaySamples: [HealthSample] = []

    var body: some View {
        NavigationStack {
            List {
                Section("Сьогодні по годинах") {
                    if hourlySteps.allSatisfy({ $0.value == 0 }) {
                        Text("Ще немає кроків за сьогодні").foregroundStyle(.secondary)
                    } else {
                        Chart(hourlySteps) { p in
                            BarMark(
                                x: .value("Година", p.date, unit: .hour),
                                y: .value("Кроки", p.value)
                            )
                            .foregroundStyle(.green)
                        }
                        .frame(height: 150)
                        .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                    }
                    HStack {
                        Text("Разом сьогодні")
                        Spacer()
                        Text("\(todayTotal)").bold()
                    }
                }

                Section("Кроки по днях") {
                    Picker("Період", selection: $period) {
                        ForEach(Period.allCases) { p in Text(p.rawValue).tag(p) }
                    }
                    .pickerStyle(.segmented)

                    if dailySteps.isEmpty {
                        Text("Немає даних за цей період").foregroundStyle(.secondary)
                    } else {
                        Chart(dailySteps) { p in
                            BarMark(
                                x: .value("День", p.date, unit: .day),
                                y: .value("Кроки", p.value)
                            )
                            .foregroundStyle(.green)
                        }
                        .frame(height: 180)
                        .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                    }
                    HStack {
                        Text("Разом за період")
                        Spacer()
                        Text("\(periodTotal)").bold()
                    }
                    HStack {
                        Text("У середньому за день")
                        Spacer()
                        Text("\(dailyAverage)").bold()
                    }
                }

                Section("Рух (інтенсивність)") {
                    if movementDaily.isEmpty {
                        Text("Немає даних").foregroundStyle(.secondary)
                    } else {
                        Chart(movementDaily) { p in
                            LineMark(
                                x: .value("День", p.date, unit: .day),
                                y: .value("Рух", p.value)
                            )
                            .foregroundStyle(.orange)
                        }
                        .frame(height: 140)
                        .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                    }
                }
            }
            .navigationTitle("Активність")
            .onAppear { reload() }
            .onChange(of: period) { _, _ in reload() }
            .onChange(of: db.sampleCount) { _, _ in reload() }
        }
    }

    private var hourlySteps: [DayValue] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: todaySamples) { s -> Date in
            let d = Date(timeIntervalSince1970: TimeInterval(s.ts))
            return cal.dateInterval(of: .hour, for: d)?.start ?? d
        }
        return grouped.map { DayValue(date: $0.key, value: Double($0.value.compactMap(\.steps).reduce(0, +))) }
            .sorted { $0.date < $1.date }
    }

    private var todayTotal: Int { todaySamples.compactMap(\.steps).reduce(0, +) }

    private var dailySteps: [DayValue] {
        aggregateDaily(periodSamples) { Double($0.compactMap(\.steps).reduce(0, +)) }
    }

    private var periodTotal: Int { periodSamples.compactMap(\.steps).reduce(0, +) }

    private var dailyAverage: Int { dailySteps.isEmpty ? 0 : periodTotal / dailySteps.count }

    private var movementDaily: [DayValue] {
        aggregateDaily(periodSamples) { group in
            let ms = group.compactMap(\.movement)
            return ms.isEmpty ? 0 : ms.reduce(0, +) / Double(ms.count)
        }
    }

    private func aggregateDaily(_ samples: [HealthSample], _ value: ([HealthSample]) -> Double) -> [DayValue] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: samples) { s in
            cal.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(s.ts)))
        }
        return grouped.map { DayValue(date: $0.key, value: value($0.value)) }
            .sorted { $0.date < $1.date }
    }

    private func reload() {
        let now = Date().addingTimeInterval(600)
        todaySamples = db.samples(from: Calendar.current.startOfDay(for: Date()), to: now)
        periodSamples = db.samples(from: Calendar.current.startOfDay(for: Date().addingTimeInterval(TimeInterval(-(period.days - 1) * 86400))), to: now)
    }
}
