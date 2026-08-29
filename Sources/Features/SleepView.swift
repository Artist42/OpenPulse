import SwiftUI
import Charts

extension SleepPhase {
    var label: String {
        switch self {
        case .deep: return "Глибокий"
        case .light: return "Легкий"
        case .awake: return "Пробудження"
        }
    }
    var color: Color {
        switch self {
        case .deep: return .indigo
        case .light: return .cyan
        case .awake: return .orange
        }
    }
}

struct SleepView: View {
    enum Period: String, CaseIterable, Identifiable {
        case night = "Ніч"
        case week = "Тиждень"
        case month = "Місяць"
        var id: String { rawValue }
    }

    struct NightBar: Identifiable {
        let date: Date
        let phase: SleepPhase
        let hours: Double
        var id: String { "\(date.timeIntervalSince1970)-\(phase.rawValue)" }
    }

    @ObservedObject var db = AppDatabase.shared
    @State private var period: Period = .night
    @State private var nights: [SleepNight] = []
    @State private var selectedIndex = 0

    var body: some View {
        NavigationStack {
            List {
                Picker("Період", selection: $period) {
                    ForEach(Period.allCases) { p in Text(p.rawValue).tag(p) }
                }
                .pickerStyle(.segmented)

                if nights.isEmpty {
                    Text("Поки немає жодної розпізнаної ночі — переконайтесь, що історія синхронізована")
                        .foregroundStyle(.secondary)
                } else {
                    switch period {
                    case .night: nightSections
                    case .week: weekSections
                    case .month: monthSections
                    }
                }
            }
            .navigationTitle("Сон")
            .onAppear { reload() }
            .onChange(of: db.sampleCount) { _, _ in reload() }
        }
    }

    // MARK: - Ніч

    private var selectedNight: SleepNight? {
        nights.indices.contains(selectedIndex) ? nights[selectedIndex] : nil
    }

    @ViewBuilder
    private var nightSections: some View {
        Section {
            HStack {
                Button { selectedIndex -= 1 } label: { Image(systemName: "chevron.left") }
                    .disabled(selectedIndex <= 0)
                Spacer()
                Text(selectedNight.map { "Ніч на \($0.wakeDate.formatted(.dateTime.weekday(.wide).day().month()))" } ?? "—")
                    .font(.headline)
                Spacer()
                Button { selectedIndex += 1 } label: { Image(systemName: "chevron.right") }
                    .disabled(selectedIndex >= nights.count - 1)
            }
            .buttonStyle(.borderless)
        }

        if let night = selectedNight {
            Section("Фази") {
                Chart(night.segments) { seg in
                    RectangleMark(
                        xStart: .value("Початок", seg.start),
                        xEnd: .value("Кінець", seg.end),
                        y: .value("Фаза", seg.phase.label)
                    )
                    .foregroundStyle(seg.phase.color)
                    .cornerRadius(3)
                }
                .chartYScale(domain: [SleepPhase.awake.label, SleepPhase.light.label, SleepPhase.deep.label])
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 2)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour())
                    }
                }
                .frame(height: 170)
                .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
            }

            Section("Підсумок") {
                row("Засинання", SleepFormat.time(night.bedtime))
                row("Прокидання", SleepFormat.time(night.wakeTime))
                row("Разом сну", SleepFormat.duration(night.asleepDuration))
                row("Глибокий", "\(SleepFormat.duration(night.deepDuration)) · \(percent(night.deepDuration, of: night.asleepDuration))")
                row("Легкий", "\(SleepFormat.duration(night.lightDuration)) · \(percent(night.lightDuration, of: night.asleepDuration))")
                row("Пробуджень", night.awakeningsCount == 0 ? "немає" : "\(night.awakeningsCount) · \(SleepFormat.duration(night.awakeDuration))")
            }
        }
    }

    // MARK: - Тиждень

    @ViewBuilder
    private var weekSections: some View {
        let week = Array(nights.suffix(7))
        Section("Тривалість по ночах") {
            Chart(bars(for: week)) { bar in
                BarMark(
                    x: .value("Ніч", bar.date, unit: .day),
                    y: .value("Годин", bar.hours)
                )
                .foregroundStyle(by: .value("Фаза", bar.phase.label))
            }
            .chartForegroundStyleScale([
                SleepPhase.deep.label: SleepPhase.deep.color,
                SleepPhase.light.label: SleepPhase.light.color,
            ])
            .frame(height: 190)
            .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
        }
        summarySection(for: week, title: "Підсумок тижня")
    }

    // MARK: - Місяць

    @ViewBuilder
    private var monthSections: some View {
        Section("Тривалість по ночах") {
            Chart {
                ForEach(nights) { night in
                    BarMark(
                        x: .value("Ніч", night.wakeDate, unit: .day),
                        y: .value("Годин", night.asleepDuration / 3600)
                    )
                    .foregroundStyle(.indigo)
                }
                if let avg = averageDuration(nights) {
                    RuleMark(y: .value("Середнє", avg / 3600))
                        .foregroundStyle(.orange)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                }
            }
            .frame(height: 190)
            .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
        }
        summarySection(for: nights, title: "Підсумок місяця")
    }

    // MARK: - Спільне

    private func summarySection(for nights: [SleepNight], title: String) -> some View {
        Section(title) {
            row("Ночей із даними", "\(nights.count)")
            row("Середня тривалість", averageDuration(nights).map(SleepFormat.duration) ?? "—")
            row("Найдовша ніч", nights.map(\.asleepDuration).max().map(SleepFormat.duration) ?? "—")
            if let bed = clockStats(nights.compactMap(\.bedtime)) {
                row("Засинання (середнє)", "\(bed.avg) ± \(bed.spread) хв")
            }
            if let wake = clockStats(nights.compactMap(\.wakeTime)) {
                row("Прокидання (середнє)", "\(wake.avg) ± \(wake.spread) хв")
            }
        }
    }

    private func bars(for nights: [SleepNight]) -> [NightBar] {
        nights.flatMap { n in
            [
                NightBar(date: n.wakeDate, phase: .deep, hours: n.deepDuration / 3600),
                NightBar(date: n.wakeDate, phase: .light, hours: n.lightDuration / 3600),
            ]
        }
    }

    private func averageDuration(_ nights: [SleepNight]) -> TimeInterval? {
        guard !nights.isEmpty else { return nil }
        return nights.map(\.asleepDuration).reduce(0, +) / Double(nights.count)
    }

    // Середній час на циферблаті + розкид. Рахуємо у хвилинах від 18:00,
    // щоб перехід через північ не ламав середнє.
    private func clockStats(_ dates: [Date]) -> (avg: String, spread: Int)? {
        guard !dates.isEmpty else { return nil }
        let cal = Calendar.current
        let offsets = dates.map { d -> Double in
            let c = cal.dateComponents([.hour, .minute], from: d)
            let m = Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
            return m >= 18 * 60 ? m - 18 * 60 : m + 6 * 60
        }
        let avg = offsets.reduce(0, +) / Double(offsets.count)
        let spread = offsets.map { abs($0 - avg) }.reduce(0, +) / Double(offsets.count)
        var minutes = Int(avg.rounded()) + 18 * 60
        if minutes >= 24 * 60 { minutes -= 24 * 60 }
        return (String(format: "%02d:%02d", minutes / 60, minutes % 60), Int(spread.rounded()))
    }

    private func percent(_ part: TimeInterval, of total: TimeInterval) -> String {
        total > 0 ? "\(Int((part / total * 100).rounded()))%" : "—"
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack { Text(title); Spacer(); Text(value).bold() }
    }

    private func reload() {
        let from = Calendar.current.startOfDay(for: Date()).addingTimeInterval(-32 * 86400)
        let samples = db.samples(from: from, to: Date().addingTimeInterval(600))
        nights = SleepIntervalBuilder.nights(from: samples)
        selectedIndex = max(0, nights.count - 1)
    }
}
