import SwiftUI
import Charts

struct TrendsView: View {
    struct DayMetrics: Identifiable {
        let date: Date
        let steps: Int
        let restingHR: Double?
        var id: Date { date }
    }

    struct ScatterPoint: Identifiable {
        let id = UUID()
        let sleep: Double
        let rhr: Double
    }

    @ObservedObject var db = AppDatabase.shared
    @State private var days: [DayMetrics] = []
    @State private var nights: [SleepNight] = []

    var body: some View {
        NavigationStack {
            List {
                Section("Цей тиждень проти минулого") {
                    compareRow("Кроки за день", thisWeekSteps, lastWeekSteps) { "\(Int($0.rounded()))" }
                    compareRow("Сон за ніч", thisWeekSleep, lastWeekSleep) { SleepFormat.duration($0) }
                    compareRow("Пульс у спокої", thisWeekRHR, lastWeekRHR, lowerIsBetter: true) { "\(Int($0.rounded())) уд/хв" }
                    compareRow("Глибокий сон", thisWeekDeepShare, lastWeekDeepShare) { "\(Int(($0 * 100).rounded()))%" }
                }

                Section("Рекорди за 30 днів") {
                    recordRow("Найбільше кроків", days.max { $0.steps < $1.steps }.map { ("\($0.steps)", $0.date) })
                    recordRow("Найдовший сон", nights.max { $0.asleepDuration < $1.asleepDuration }.map { (SleepFormat.duration($0.asleepDuration), $0.wakeDate) })
                    recordRow("Найнижчий пульс у спокої", days.filter { $0.restingHR != nil }.min { ($0.restingHR ?? 0) < ($1.restingHR ?? 0) }.map { ("\(Int(($0.restingHR ?? 0).rounded())) уд/хв", $0.date) })
                }

                Section("Кореляція: сон ↔ пульс у спокої") {
                    if let r = correlation {
                        Chart(scatterPoints) { p in
                            PointMark(
                                x: .value("Сон, год", p.sleep),
                                y: .value("Пульс у спокої", p.rhr)
                            )
                            .foregroundStyle(.purple)
                        }
                        .chartXScale(domain: .automatic(includesZero: false))
                        .chartYScale(domain: .automatic(includesZero: false))
                        .frame(height: 170)
                        .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                        row("Коефіцієнт r", String(format: "%.2f", r))
                        Text(interpretation(r))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Замало пар «ніч + день» — потрібно щонайменше 7 ночей із пульсом")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Тренди")
            .onAppear { reload() }
            .onChange(of: db.sampleCount) { _, _ in reload() }
        }
    }

    // MARK: - Тижневі агрегати

    private var thisWeekSteps: Double? { avg(days.suffix(7).map { Double($0.steps) }) }
    private var lastWeekSteps: Double? { avg(days.dropLast(7).suffix(7).map { Double($0.steps) }) }
    private var thisWeekRHR: Double? { avg(days.suffix(7).compactMap(\.restingHR)) }
    private var lastWeekRHR: Double? { avg(days.dropLast(7).suffix(7).compactMap(\.restingHR)) }
    private var thisWeekSleep: Double? { avg(nights.suffix(7).map(\.asleepDuration)) }
    private var lastWeekSleep: Double? { avg(nights.dropLast(7).suffix(7).map(\.asleepDuration)) }
    private var thisWeekDeepShare: Double? { deepShare(Array(nights.suffix(7))) }
    private var lastWeekDeepShare: Double? { deepShare(Array(nights.dropLast(7).suffix(7))) }

    private func avg(_ v: [Double]) -> Double? {
        v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
    }

    private func deepShare(_ n: [SleepNight]) -> Double? {
        let total = n.reduce(0.0) { $0 + $1.asleepDuration }
        guard total > 0 else { return nil }
        return n.reduce(0.0) { $0 + $1.deepDuration } / total
    }

    // MARK: - Кореляція (Пірсон)

    private var correlationPairs: [(sleep: Double, rhr: Double)] {
        nights.compactMap { n in
            guard let day = days.first(where: { Calendar.current.isDate($0.date, inSameDayAs: n.wakeDate) }),
                  let rhr = day.restingHR else { return nil }
            return (n.asleepDuration / 3600, rhr)
        }
    }

    private var scatterPoints: [ScatterPoint] {
        correlationPairs.map { ScatterPoint(sleep: $0.sleep, rhr: $0.rhr) }
    }

    private var correlation: Double? {
        let p = correlationPairs
        guard p.count >= 7 else { return nil }
        let n = Double(p.count)
        let sx = p.reduce(0.0) { $0 + $1.sleep }
        let sy = p.reduce(0.0) { $0 + $1.rhr }
        let sxx = p.reduce(0.0) { $0 + $1.sleep * $1.sleep }
        let syy = p.reduce(0.0) { $0 + $1.rhr * $1.rhr }
        let sxy = p.reduce(0.0) { $0 + $1.sleep * $1.rhr }
        let num = n * sxy - sx * sy
        let den = ((n * sxx - sx * sx) * (n * syy - sy * sy)).squareRoot()
        guard den > 0 else { return nil }
        return num / den
    }

    private func interpretation(_ r: Double) -> String {
        switch r {
        case ..<(-0.3): return "Помітний зв'язок: що довший сон, то нижчий пульс у спокої."
        case ..<(-0.1): return "Слабкий зв'язок: довший сон трохи знижує пульс у спокої."
        case ...0.1: return "Виразного зв'язку на цій вибірці не видно."
        default: return "Несподівано: довший сон збігається з вищим пульсом — вибірка ще замала або період нетиповий."
        }
    }

    // MARK: - UI-хелпери

    private func compareRow(_ title: String, _ current: Double?, _ previous: Double?, lowerIsBetter: Bool = false, format: (Double) -> String) -> some View {
        HStack {
            Text(title)
            Spacer()
            if let c = current {
                if let p = previous, abs(c - p) > 0.0001 {
                    Image(systemName: c > p ? "arrow.up" : "arrow.down")
                        .font(.caption)
                        .foregroundStyle((lowerIsBetter ? c < p : c > p) ? Color.green : Color.red)
                }
                Text(format(c)).bold()
            } else {
                Text("—").bold()
            }
        }
    }

    private func recordRow(_ title: String, _ value: (String, Date)?) -> some View {
        HStack {
            Text(title)
            Spacer()
            if let v = value {
                Text(v.1.formatted(.dateTime.day().month())).font(.footnote).foregroundStyle(.secondary)
                Text(v.0).bold()
            } else {
                Text("—").bold()
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack { Text(title); Spacer(); Text(value).bold() }
    }

    private func reload() {
        let cal = Calendar.current
        let from = cal.startOfDay(for: Date()).addingTimeInterval(-32 * 86400)
        let samples = db.samples(from: from, to: Date().addingTimeInterval(600))
        nights = SleepIntervalBuilder.nights(from: samples)

        let grouped = Dictionary(grouping: samples) { s in
            cal.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(s.ts)))
        }
        days = grouped.map { date, group -> DayMetrics in
            let hrs = group.compactMap(\.hr).sorted()
            let k = max(1, hrs.count / 10)
            let rhr = hrs.isEmpty ? nil : hrs.prefix(k).reduce(0, +) / Double(k)
            return DayMetrics(date: date, steps: group.compactMap(\.steps).reduce(0, +), restingHR: rhr)
        }
        .sorted { $0.date < $1.date }
    }
}
