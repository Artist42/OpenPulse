import Foundation
import SwiftUI

// Складова індексу готовності: скільки балів набрано з можливих і чому.
struct ReadinessComponent: Identifiable {
    let name: String
    let points: Double
    let maxPoints: Double
    let detail: String
    var id: String { name }
    var fraction: Double { maxPoints > 0 ? min(1, points / maxPoints) : 0 }
}

struct ReadinessResult {
    let score: Int              // 0–100
    let zoneName: String
    let advice: String
    let components: [ReadinessComponent]

    var zoneColor: Color {
        switch score {
        case 80...: return .green
        case 60...: return .teal
        case 40...: return .orange
        default: return .red
        }
    }
}

// Індекс готовності (аналог Fitbit Daily Readiness) із сирих даних.
// Рахується після останньої ночі сну. 100 балів = 4 складові:
//   Сон (40)          — тривалість/глибина/безперервність проти ВАШОЇ норми
//   Нічний пульс (30) — пульс у спокої цієї ночі проти базової лінії
//   Навантаження (20) — вчорашні кроки проти типового дня (перевтома → мінус)
//   Температура (10)  — відхилення нічної температури від базової
// Складова без даних не штрафує: скор рахується від доступного максимуму.
enum ReadinessCalculator {
    // --- Ваги (сума 100) ---
    static let sleepMax = 40.0
    static let hrMax = 30.0
    static let loadMax = 20.0
    static let tempMax = 10.0

    // --- Пороги (усі — для калібрування) ---
    static let fallbackSleep: TimeInterval = 7.5 * 3600 // норма сну, поки мало історії
    static let fallbackDeepShare = 0.18   // звична частка глибокого, поки мало історії
    static let awakeZeroShare = 0.20      // стільки пробуджень за ніч → 0 балів безперервності
    static let hrPenaltyBpm = 8.0         // на стільки уд/хв вище базової → 0 балів пульсу
    static let loadComfort = 1.25         // вчора ≤ 125% типових кроків — без штрафу
    static let loadCeiling = 2.2          // ≥ 220% типових — максимальний штраф
    static let loadFloor = 8.0            // мінімум балів навантаження
    static let tempFree = 0.3             // °C відхилення без штрафу
    static let tempZero = 1.2             // °C відхилення → 0 балів
    static let maxWakeAge: TimeInterval = 36 * 3600 // ніч старша — скору немає

    static func calculate(samples: [HealthSample], nights: [SleepNight],
                          now: Date = Date(), calendar: Calendar = .current) -> ReadinessResult? {
        guard let night = nights.last, let wake = night.wakeTime,
              now.timeIntervalSince(wake) <= maxWakeAge else { return nil }
        let history = Array(nights.dropLast())
        var parts: [ReadinessComponent] = []

        // 1. Сон (40): тривалість (22) + глибина (10) + безперервність (8).
        let baseSleep = median(history.suffix(14).map(\.asleepDuration)) ?? fallbackSleep
        let durPoints = 22 * min(1, night.asleepDuration / max(baseSleep, 3600))
        let deepShare = night.asleepDuration > 0 ? night.deepDuration / night.asleepDuration : 0
        let deepShares = history.suffix(14).filter { $0.asleepDuration > 0 }
            .map { $0.deepDuration / $0.asleepDuration }
        let baseDeep = median(deepShares) ?? fallbackDeepShare
        let deepPoints = 10 * (baseDeep > 0 ? min(1, deepShare / baseDeep) : 1)
        let inBed = night.asleepDuration + night.awakeDuration
        let awakeShare = inBed > 0 ? night.awakeDuration / inBed : 0
        let contPoints = 8 * (1 - min(1, awakeShare / awakeZeroShare))
        parts.append(ReadinessComponent(
            name: "Сон",
            points: durPoints + deepPoints + contPoints,
            maxPoints: sleepMax,
            detail: "\(SleepFormat.duration(night.asleepDuration)) проти звичних \(SleepFormat.duration(baseSleep))"
        ))

        // 2. Нічний пульс (30): нижні 10% довіреного пульсу цієї ночі проти
        //    медіани попередніх ночей. Вище базової — гірше відновлення.
        if let nightHR = restingHR(in: night, samples: samples) {
            let baseHRs = history.suffix(30).compactMap { restingHR(in: $0, samples: samples) }
            let baseHR = median(baseHRs) ?? nightHR
            let delta = nightHR - baseHR
            let points = hrMax * (1 - min(1, max(0, delta) / hrPenaltyBpm))
            parts.append(ReadinessComponent(
                name: "Нічний пульс",
                points: points,
                maxPoints: hrMax,
                detail: String(format: "%.0f уд/хв (базова лінія %.0f)", nightHR, baseHR)
            ))
        }

        // 3. Навантаження вчора (20): значно більше типового → тілу треба
        //    більше відновлення, готовність нижча.
        let today = calendar.startOfDay(for: now)
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today) {
            let ySteps = steps(on: yesterday, samples: samples)
            let totals = dailyStepTotals(samples: samples, excluding: [today, yesterday], calendar: calendar)
            if let typical = median(totals), typical >= 500, ySteps > 0 {
                let ratio = Double(ySteps) / typical
                let over = max(0, ratio - loadComfort) / (loadCeiling - loadComfort)
                let points = loadMax - (loadMax - loadFloor) * min(1, over)
                parts.append(ReadinessComponent(
                    name: "Навантаження вчора",
                    points: points,
                    maxPoints: loadMax,
                    detail: "\(ySteps) кроків (типовий день ≈ \(Int(typical)))"
                ))
            }
        }

        // 4. Температура вночі (10): проти базової лінії попередніх ночей.
        if let nightT = nightTemperature(in: night, samples: samples) {
            let baseTs = history.suffix(30).compactMap { nightTemperature(in: $0, samples: samples) }
            if let baseT = median(baseTs) {
                let dev = abs(nightT - baseT)
                let over = max(0, dev - tempFree) / (tempZero - tempFree)
                let points = tempMax * (1 - min(1, over))
                parts.append(ReadinessComponent(
                    name: "Температура вночі",
                    points: points,
                    maxPoints: tempMax,
                    detail: String(format: "%.1f° (базова %.1f°)", nightT, baseT)
                ))
            }
        }

        let maxTotal = parts.reduce(0.0) { $0 + $1.maxPoints }
        guard maxTotal > 0 else { return nil }
        let earned = parts.reduce(0.0) { $0 + $1.points }
        let score = Int((100 * earned / maxTotal).rounded())

        let zone: (String, String)
        switch score {
        case 80...: zone = ("Відмінна готовність", "Тіло відновилося — день підходить для великих навантажень.")
        case 60...: zone = ("Добра готовність", "Можна діяти у звичному ритмі.")
        case 40...: zone = ("Помірна готовність", "Без рекордів: помірне навантаження і раніше в ліжко.")
        default: zone = ("Низька готовність", "День відновлення: прогулянка замість тренування, більше сну.")
        }
        return ReadinessResult(score: score, zoneName: zone.0, advice: zone.1, components: parts)
    }

    // MARK: - Допоміжні

    private static func samplesBetween(_ from: Date, _ to: Date, _ samples: [HealthSample]) -> [HealthSample] {
        let a = Int(from.timeIntervalSince1970)
        let b = Int(to.timeIntervalSince1970)
        return samples.filter { $0.ts >= a && $0.ts <= b }
    }

    // Пульс у спокої за ніч: середнє найнижчих 10% довірених замірів.
    private static func restingHR(in night: SleepNight, samples: [HealthSample]) -> Double? {
        guard let from = night.bedtime, let to = night.wakeTime else { return nil }
        let hrs = samplesBetween(from, to, samples).compactMap(\.validHR).sorted()
        guard hrs.count >= 5 else { return nil }
        let k = max(1, hrs.count / 10)
        return hrs.prefix(k).reduce(0, +) / Double(k)
    }

    // Середня температура за ніч (тільки коли годинник на руці).
    private static func nightTemperature(in night: SleepNight, samples: [HealthSample]) -> Double? {
        guard let from = night.bedtime, let to = night.wakeTime else { return nil }
        let temps = samplesBetween(from, to, samples)
            .filter { $0.activity != "NOT_WORN" }
            .compactMap(\.temperature)
            .filter { $0 > 10 } // явні артефакти «не на руці» відкидаємо
        guard temps.count >= 5 else { return nil }
        return temps.reduce(0, +) / Double(temps.count)
    }

    private static func steps(on day: Date, samples: [HealthSample]) -> Int {
        samplesBetween(day, day.addingTimeInterval(86400), samples)
            .compactMap(\.steps)
            .reduce(0, +)
    }

    // Сумарні кроки по днях (для «типового дня»), без вказаних днів.
    private static func dailyStepTotals(samples: [HealthSample], excluding: [Date], calendar: Calendar) -> [Double] {
        var byDay: [Date: Int] = [:]
        for s in samples {
            let day = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(s.ts)))
            byDay[day, default: 0] += s.steps ?? 0
        }
        return byDay
            .filter { !excluding.contains($0.key) && $0.value > 0 }
            .map { Double($0.value) }
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let s = values.sorted()
        return s[s.count / 2]
    }
}
