import Foundation

enum SleepPhase: String, Codable {
    case light, deep, awake
}

struct SleepSegment: Identifiable {
    let start: Date
    let end: Date
    let phase: SleepPhase
    var id: Date { start }
    var duration: TimeInterval { end.timeIntervalSince(start) }
}

struct SleepNight: Identifiable {
    let wakeDate: Date          // календарний день прокидання
    let segments: [SleepSegment]
    var id: Date { wakeDate }

    var bedtime: Date? { segments.first?.start }
    var wakeTime: Date? { segments.last?.end }
    var asleepDuration: TimeInterval { segments.filter { $0.phase != .awake }.reduce(0) { $0 + $1.duration } }
    var deepDuration: TimeInterval { segments.filter { $0.phase == .deep }.reduce(0) { $0 + $1.duration } }
    var lightDuration: TimeInterval { segments.filter { $0.phase == .light }.reduce(0) { $0 + $1.duration } }
    var awakeDuration: TimeInterval { segments.filter { $0.phase == .awake }.reduce(0) { $0 + $1.duration } }
    var awakeningsCount: Int { segments.filter { $0.phase == .awake }.count }
}

enum SleepFormat {
    static func duration(_ t: TimeInterval) -> String {
        let m = Int((t / 60).rounded())
        return m < 60 ? "\(m) хв" : "\(m / 60) год \(String(format: "%02d", m % 60)) хв"
    }
    static func time(_ d: Date?) -> String {
        d?.formatted(date: .omitted, time: .shortened) ?? "—"
    }
}

enum SleepIntervalBuilder {
    // Параметри алгоритму. Інтервал запису НЕ хардкодиться:
    // тривалість слота виводиться з даних, тому 3-хв і 10-хв історія співіснують.
    static let minSlot: TimeInterval = 60          // коротші дельти вважаємо шумом
    static let maxSlot: TimeInterval = 15 * 60     // більша дірка — слот не розтягуємо
    static let defaultSlot: TimeInterval = 3 * 60  // запасне значення (поточне налаштування Health)
    static let mergeGapFactor = 1.8                // мікророзриви ≤ 1.8 типового кроку зшиваємо
    static let maxAwakeGap: TimeInterval = 60 * 60 // розрив ≤ 60 хв усередині ночі = «пробудження»
    static let minSession: TimeInterval = 40 * 60  // коротші сесії не вважаємо нічним сном

    static func nights(from samples: [HealthSample], calendar: Calendar = .current) -> [SleepNight] {
        let sorted = samples.sorted { $0.ts < $1.ts }
        guard sorted.count > 1 else { return [] }

        // 1. Типовий крок запису — медіана відстаней між сусідніми записами.
        var deltas: [TimeInterval] = []
        for i in 1..<sorted.count {
            let d = TimeInterval(sorted[i].ts - sorted[i - 1].ts)
            if d >= minSlot && d <= maxSlot { deltas.append(d) }
        }
        let typical = deltas.isEmpty ? defaultSlot : deltas.sorted()[deltas.count / 2]

        // 2. Сирі слоти сну: запис із міткою t покриває [t − слот, t].
        struct Slot { var start: Date; var end: Date; let phase: SleepPhase }
        var slots: [Slot] = []
        for (i, s) in sorted.enumerated() {
            let phase: SleepPhase
            switch s.activity {
            case "DEEP_SLEEP": phase = .deep
            case "LIGHT_SLEEP": phase = .light
            default: continue
            }
            var slot = typical
            if i > 0 {
                let d = TimeInterval(s.ts - sorted[i - 1].ts)
                if d >= minSlot && d <= maxSlot { slot = d }
            }
            let end = Date(timeIntervalSince1970: TimeInterval(s.ts))
            slots.append(Slot(start: end.addingTimeInterval(-slot), end: end, phase: phase))
        }
        guard !slots.isEmpty else { return [] }

        // 3. Зшивання сусідніх слотів однієї фази (мікророзриви допускаємо).
        var segments: [SleepSegment] = []
        var cur = slots[0]
        for slot in slots.dropFirst() {
            let gap = slot.start.timeIntervalSince(cur.end)
            if slot.phase == cur.phase && gap <= typical * mergeGapFactor {
                cur.end = slot.end
            } else {
                segments.append(SleepSegment(start: cur.start, end: cur.end, phase: cur.phase))
                cur = slot
            }
        }
        segments.append(SleepSegment(start: cur.start, end: cur.end, phase: cur.phase))

        // 4. Групування в сесії: розрив ≤ 60 хв стає сегментом «Пробудження».
        var sessions: [[SleepSegment]] = []
        var current: [SleepSegment] = []
        for seg in segments {
            if let last = current.last {
                let gap = seg.start.timeIntervalSince(last.end)
                if gap > maxAwakeGap {
                    sessions.append(current)
                    current = [seg]
                    continue
                }
                if gap > typical * mergeGapFactor {
                    current.append(SleepSegment(start: last.end, end: seg.start, phase: .awake))
                }
            }
            current.append(seg)
        }
        if !current.isEmpty { sessions.append(current) }

        // 5. Головна сесія кожної ночі — найдовша; дрімоту поки ігноруємо.
        //    Ніч прив'язується до календарного дня прокидання.
        var byNight: [Date: [SleepSegment]] = [:]
        for session in sessions {
            let asleep = session.filter { $0.phase != .awake }.reduce(0.0) { $0 + $1.duration }
            guard asleep >= minSession, let end = session.last?.end else { continue }
            let night = calendar.startOfDay(for: end)
            let existing = byNight[night]?.filter { $0.phase != .awake }.reduce(0.0) { $0 + $1.duration } ?? 0
            if asleep > existing { byNight[night] = session }
        }
        return byNight
            .map { SleepNight(wakeDate: $0.key, segments: $0.value) }
            .sorted { $0.wakeDate < $1.wakeDate }
    }
}
