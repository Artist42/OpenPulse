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

// Класифікатор сну v2: мітки активності годинника ІГНОРУЮТЬСЯ (крім NOT_WORN).
// Сон визначається як у Fitbit — комбінацією руху та пульсу відносно
// особистої базової лінії. Усі пороги зібрані нижче для калібрування.
enum SleepIntervalBuilder {
    // --- Крок запису (виводиться з даних, не хардкодиться) ---
    static let minSlot: TimeInterval = 60
    static let maxSlot: TimeInterval = 15 * 60
    static let defaultSlot: TimeInterval = 3 * 60

    // --- Пороги класифікації (див. таблицю калібрування в інструкції) ---
    static let hrOffset: Double = 10        // «сонний» пульс ≤ пульс у спокої + 10 уд/хв
    static let deepHrOffset: Double = 3     // «глибокий» пульс ≤ пульс у спокої + 3
    static let moveHeadroom = 1.5           // запас над «тихим» рухом (30-й перцентиль)
    static let deepMoveFactor = 0.4         // глибокий: рух ≤ 40% порогу
    static let entryMinutes: Double = 21    // стільки хвилин тиші поспіль = засинання
    static let mergeGapFactor = 1.8         // мікророзриви ≤ 1.8 кроку зшиваємо
    static let maxAwakeGap: TimeInterval = 60 * 60 // розрив ≤ 60 хв = «пробудження»
    static let minSession: TimeInterval = 40 * 60  // коротші сесії — не нічний сон

    private struct SlotInfo {
        let start: Date
        let end: Date
        let movementPerMin: Double
        let hr: Double?
        let steps: Int
        let worn: Bool
    }

    static func nights(from samples: [HealthSample], calendar: Calendar = .current) -> [SleepNight] {
        let sorted = samples.sorted { $0.ts < $1.ts }
        guard sorted.count > 5 else { return [] }

        // 1. Типовий крок запису — медіана відстаней між сусідніми записами.
        var deltas: [TimeInterval] = []
        for i in 1..<sorted.count {
            let d = TimeInterval(sorted[i].ts - sorted[i - 1].ts)
            if d >= minSlot && d <= maxSlot { deltas.append(d) }
        }
        let typical = deltas.isEmpty ? defaultSlot : deltas.sorted()[deltas.count / 2]

        // 2. Слоти з СИРИХ даних: рух за хвилину, пульс, кроки.
        var slots: [SlotInfo] = []
        for (i, s) in sorted.enumerated() {
            var slot = typical
            if i > 0 {
                let d = TimeInterval(s.ts - sorted[i - 1].ts)
                if d >= minSlot && d <= maxSlot { slot = d }
            }
            let end = Date(timeIntervalSince1970: TimeInterval(s.ts))
            slots.append(SlotInfo(
                start: end.addingTimeInterval(-slot),
                end: end,
                movementPerMin: Double(s.movement ?? 0) / (slot / 60),
                hr: s.hr,
                steps: s.steps ?? 0,
                worn: s.activity != "NOT_WORN"
            ))
        }

        // 3. Особиста базова лінія: пульс у спокої = середнє найнижчих 10% замірів.
        let hrs = slots.compactMap { $0.hr }.filter { $0 > 30 }.sorted()
        let k = max(1, hrs.count / 10)
        let restingHR: Double? = hrs.isEmpty ? nil : hrs.prefix(k).reduce(0, +) / Double(k)

        // 4. Поріг «тихого» руху: 30-й перцентиль ненульового руху × запас.
        let moves = slots.map { $0.movementPerMin }.filter { $0 > 0 }.sorted()
        let quietMove = moves.isEmpty ? 1.0 : moves[Int(Double(moves.count - 1) * 0.3)]
        let moveThreshold = quietMove * moveHeadroom

        // 5. Кандидат сну: годинник на руці, нуль кроків, тихий рух І сонний пульс.
        let candidate: [Bool] = slots.map { s in
            guard s.worn, s.steps == 0, s.movementPerMin <= moveThreshold else { return false }
            if let hr = s.hr, hr > 30, let rest = restingHR { return hr <= rest + hrOffset }
            return true // якщо пульсу в слоті немає — вирішує рух
        }

        // 6. Згладжування «більшістю» у вікні з 5 слотів (прибирає поодинокі викиди).
        var smooth = candidate
        for i in slots.indices {
            let lo = max(0, i - 2)
            let hi = min(slots.count - 1, i + 2)
            let yes = (lo...hi).filter { candidate[$0] }.count
            smooth[i] = yes * 2 > hi - lo + 1
        }

        // 7. Засинання лише після entryMinutes тиші поспіль —
        //    вечір на дивані більше не вважається сном.
        let entrySlots = max(2, Int((entryMinutes * 60 / typical).rounded()))
        var asleep = [Bool](repeating: false, count: slots.count)
        var i = 0
        while i < slots.count {
            if smooth[i] {
                var j = i
                while j < slots.count && smooth[j] { j += 1 }
                if j - i >= entrySlots {
                    for x in i..<j { asleep[x] = true }
                }
                i = j
            } else {
                i += 1
            }
        }

        // 8. Фаза сонного слота: глибокий = майже без руху І пульс біля спокою.
        func phaseOf(_ s: SlotInfo) -> SleepPhase {
            let calmMove = s.movementPerMin <= moveThreshold * deepMoveFactor
            let calmHR: Bool
            if let hr = s.hr, hr > 30, let rest = restingHR {
                calmHR = hr <= rest + deepHrOffset
            } else {
                calmHR = calmMove
            }
            return calmMove && calmHR ? .deep : .light
        }

        // 9. Зшивання сонних слотів у сегменти (мікророзриви допускаємо).
        var segments: [SleepSegment] = []
        var currentStart: Date?
        var currentEnd: Date?
        var currentPhase: SleepPhase = .light
        for (idx, s) in slots.enumerated() where asleep[idx] {
            let p = phaseOf(s)
            if currentStart != nil, let ce = currentEnd,
               p == currentPhase, s.start.timeIntervalSince(ce) <= typical * mergeGapFactor {
                currentEnd = s.end
            } else {
                if let cs = currentStart, let ce = currentEnd {
                    segments.append(SleepSegment(start: cs, end: ce, phase: currentPhase))
                }
                currentStart = s.start
                currentEnd = s.end
                currentPhase = p
            }
        }
        if let cs = currentStart, let ce = currentEnd {
            segments.append(SleepSegment(start: cs, end: ce, phase: currentPhase))
        }
        guard !segments.isEmpty else { return [] }

        // 10. Групування в сесії: розрив ≤ 60 хв стає сегментом «Пробудження».
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

        // 11. Головна сесія кожної ночі — найдовша; дрімота поки ігнорується.
        var byNight: [Date: [SleepSegment]] = [:]
        for session in sessions {
            let asleepTotal = session.filter { $0.phase != .awake }.reduce(0.0) { $0 + $1.duration }
            guard asleepTotal >= minSession, let end = session.last?.end else { continue }
            let night = calendar.startOfDay(for: end)
            let existing = byNight[night]?.filter { $0.phase != .awake }.reduce(0.0) { $0 + $1.duration } ?? 0
            if asleepTotal > existing { byNight[night] = session }
        }
        return byNight
            .map { SleepNight(wakeDate: $0.key, segments: $0.value) }
            .sorted { $0.wakeDate < $1.wakeDate }
    }
}
