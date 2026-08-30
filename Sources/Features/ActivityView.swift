import SwiftUI
import Charts

struct ActivityView: View {
    enum Period: String, CaseIterable, Identifiable {
        case week = "Тиждень"
        case month = "Місяць"
        var id: String { rawValue }
        var days: Int { self == .week ? 7 : 30 }
    }

    enum DetailWindow: String, CaseIterable, Identifiable {
        case h1 = "1 год"
        case h3 = "3 год"
        case h6 = "6 год"
        case day = "Доба"
        var id: String { rawValue }
        var seconds: Int {
            switch self {
            case .h1: return 3600
            case .h3: return 3 * 3600
            case .h6: return 6 * 3600
            case .day: return 24 * 3600
            }
        }
    }

    struct SlotPoint: Identifiable {
        let date: Date
        let steps: Int
        let movement: Double
        var id: Date { date }
    }

    @ObservedObject var db = AppDatabase.shared
    @State private var period: Period = .week
    @State private var periodSamples: [HealthSample] = []
    @State private var todaySamples: [HealthSample] = []

    @State private var detailDay = Calendar.current.startOfDay(for: Date())
    @State private var detailSamples: [HealthSample] = []
    @State private var detailWindow: DetailWindow = .h3
    @State private var selectedTime: Date?

    var body: some View {
        NavigationStack {
            List {
                detailSection
                todaySection
                dailySection
                movementSection
            }
            .navigationTitle("Активність")
            .onAppear { reload() }
            .onChange(of: period) { _, _ in reload() }
            .onChange(of: detailDay) { _, _ in reloadDetail() }
            .onChange(of: db.sampleCount) { _, _ in reload() }
        }
    }

    // MARK: - Детальний перегляд дня (кожен слот запису)

    private var detailSection: some View {
        Section("Детально (кожен слот запису)") {
            HStack {
                Button { shiftDetailDay(-1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless)
                Spacer()
                Text(detailDay.formatted(date: .abbreviated, time: .omitted)).bold()
                Spacer()
                Button { shiftDetailDay(1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.borderless)
                    .disabled(Calendar.current.isDateInToday(detailDay))
            }

            Picker("Вікно", selection: $detailWindow) {
                ForEach(DetailWindow.allCases) { w in Text(w.rawValue).tag(w) }
            }
            .pickerStyle(.segmented)

            if slotPoints.isEmpty {
                Text("Немає даних за цей день").foregroundStyle(.secondary)
            } else {
                Chart(slotPoints) { p in
                    BarMark(
                        x: .value("Час", p.date),
                        y: .value("Кроки", p.steps),
                        width: .fixed(3)
                    )
                    .foregroundStyle(.green)
                }
                .chartScrollableAxes(.horizontal)
                .chartXVisibleDomain(length: detailWindow.seconds)
                .chartXSelection(value: $selectedTime)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour().minute())
                    }
                }
                .frame(height: 170)
                .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 4, trailing: 12))

                if let sel = selectedTime, let p = nearestSlot(to: sel) {
                    HStack {
                        Text("Слот \(p.date.formatted(date: .omitted, time: .shortened))")
                        Spacer()
                        Text("\(p.steps) кроків · рух \(Int(p.movement.rounded()))").bold()
                    }
                    .font(.footnote)
                }

                Chart(slotPoints) { p in
                    LineMark(
                        x: .value("Час", p.date),
                        y: .value("Рух", p.movement)
                    )
                    .foregroundStyle(.orange)
                }
                .chartScrollableAxes(.horizontal)
                .chartXVisibleDomain(length: detailWindow.seconds)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour().minute())
                    }
                }
                .frame(height: 100)
                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 12, trailing: 12))
            }
        }
    }

    private var slotPoints: [SlotPoint] {
        detailSamples.map { s in
            SlotPoint(
                date: Date(timeIntervalSince1970: TimeInterval(s.ts)),
                steps: s.steps ?? 0,
                movement: s.movement ?? 0
            )
        }
    }

    private func nearestSlot(to date: Date) -> SlotPoint? {
        slotPoints.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    private func shiftDetailDay(_ days: Int) {
        detailDay = Calendar.current.date(byAdding: .day, value: days, to: detailDay) ?? detailDay
        selectedTime = nil
    }

    // MARK: - Сьогодні по годинах

    private var todaySection: some View {
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
    }

    // MARK: - Кроки по днях

    private var dailySection: some View {
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
    }

    // MARK: - Рух по днях

    private var movementSection: some View {
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

    // MARK: - Обчислення

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
        reloadDetail()
    }

    private func reloadDetail() {
        detailSamples = db.samples(from: detailDay, to: detailDay.addingTimeInterval(86400))
    }
}
