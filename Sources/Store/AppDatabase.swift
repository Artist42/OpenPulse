import Foundation
import GRDB

struct HealthSample: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "samples"
    var ts: Int          // час запису, epoch у секундах — первинний ключ
    var hr: Double?      // пульс
    var steps: Int?      // кроки за 10-хв слот
    var movement: Double?
    var temperature: Double? // сире значення, інтерпретуємо пізніше (наше рішення)
    var altitude: Double?
    var battery: Double?
    var activity: String?
}

extension HealthSample {
    // Пульс, якому можна довіряти: годинник на руці і значення не артефакт (< 45).
    var validHR: Double? {
        guard activity != "NOT_WORN", let hr, hr >= 45 else { return nil }
        return hr
    }
}

// Спільні типи для графіків
struct HeartRatePoint: Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}

struct DayValue: Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}

final class AppDatabase: ObservableObject {
    static let shared = AppDatabase()
    let dbQueue: DatabaseQueue

    @Published var sampleCount: Int = 0
    @Published var lastSampleDate: Date?

    private init() {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("openpulse.sqlite")
        dbQueue = try! DatabaseQueue(path: url.path)
        try! dbQueue.write { db in
            try db.create(table: "samples", ifNotExists: true) { t in
                t.column("ts", .integer).primaryKey()
                t.column("hr", .double)
                t.column("steps", .integer)
                t.column("movement", .double)
                t.column("temperature", .double)
                t.column("altitude", .double)
                t.column("battery", .double)
                t.column("activity", .text)
            }
        }
        refreshStats()
    }

    func insert(_ samples: [HealthSample]) {
        try? dbQueue.write { db in
            for s in samples { try s.upsert(db) }
        }
        refreshStats()
    }

    func refreshStats() {
        let stats = (try? dbQueue.read { db -> (Int, Int?) in
            let c = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM samples") ?? 0
            let m = try Int.fetchOne(db, sql: "SELECT MAX(ts) FROM samples")
            return (c, m)
        }) ?? (0, nil)
        sampleCount = stats.0
        lastSampleDate = stats.1.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    func wipeAll() {
        try? dbQueue.write { db in
            try db.execute(sql: "DELETE FROM samples")
        }
        refreshStats()
    }
    
    // MARK: - Запити для екранів

    func samples(from: Date, to: Date) -> [HealthSample] {
        (try? dbQueue.read { db in
            try HealthSample.fetchAll(
                db,
                sql: "SELECT * FROM samples WHERE ts >= ? AND ts < ? ORDER BY ts",
                arguments: [Int(from.timeIntervalSince1970), Int(to.timeIntervalSince1970)]
            )
        }) ?? []
    }

    func latestHeartRate() -> HeartRatePoint? {
        let result = try? dbQueue.read { db -> (Int, Double)? in
            if let row = try Row.fetchOne(db, sql: "SELECT ts, hr FROM samples WHERE hr >= 45 AND (activity IS NULL OR activity <> 'NOT_WORN') ORDER BY ts DESC LIMIT 1") {                
                return (row["ts"], row["hr"])
            }
            return nil
        }
        guard let r = result ?? nil else { return nil }
        return HeartRatePoint(date: Date(timeIntervalSince1970: TimeInterval(r.0)), value: r.1)
    }
}
