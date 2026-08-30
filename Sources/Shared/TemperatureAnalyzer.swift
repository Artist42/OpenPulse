import Foundation

enum TemperatureAnalyzer {
    struct NightTemp: Identifiable {
        let date: Date        // день прокидання
        let median: Double    // медіанна температура за ніч
        let deviation: Double // відхилення від базової лінії
        var id: Date { date }
    }

    struct Summary {
        let baseline: Double?
        let nights: [NightTemp]
        var lastDeviation: Double? { nights.last?.deviation }
    }

    static let minNightsForBaseline = 5
    static let minSamplesPerNight = 5

    static func summary(samples: [HealthSample], nights: [SleepNight]) -> Summary {
        let temps = samples.filter { $0.temperature != nil && $0.activity != "NOT_WORN" }
        var medians: [(date: Date, value: Double)] = []
        for night in nights {
            let asleep = night.segments.filter { $0.phase != .awake }
            let values = temps.compactMap { s -> Double? in
                let d = Date(timeIntervalSince1970: TimeInterval(s.ts))
                guard asleep.contains(where: { $0.start <= d && d <= $0.end }) else { return nil }
                return s.temperature
            }
            guard values.count >= minSamplesPerNight else { continue }
            medians.append((night.wakeDate, median(values)))
        }
        guard medians.count >= minNightsForBaseline else {
            return Summary(baseline: nil, nights: [])
        }
        let base = median(medians.map(\.value))
        let nightTemps = medians.map { NightTemp(date: $0.date, median: $0.value, deviation: $0.value - base) }
        return Summary(baseline: base, nights: nightTemps)
    }

    static func median(_ values: [Double]) -> Double {
        let s = values.sorted()
        let n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }
}
