import Foundation

final class SyncEngine: ObservableObject {
    static let shared = SyncEngine()

    @Published var statusText = "Ще не синхронізувалось"
    @Published var isSyncing = false

    private var pending: [HealthSample] = []

    private var lastSync: Int {
        get { UserDefaults.standard.integer(forKey: "lastSync") }
        set { UserDefaults.standard.set(newValue, forKey: "lastSync") }
    }

    func startSync() {
        guard BLEManager.shared.isConnected else {
            statusText = "Годинник не підключено"
            return
        }
        isSyncing = true
        pending = []
        statusText = "Запит історії з годинника…"
        BLEManager.shared.send("\u{10}bwsync.start(\(lastSync));\n")
    }

    func resetCursor() { lastSync = 0 }

    func handleLine(_ line: String) {
        guard line.hasPrefix("BWS:") else { return }
        let json = String(line.dropFirst(4))
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        if let err = obj["err"] as? String {
            isSyncing = false
            statusText = "Помилка годинника: \(err)"
            return
        }

        if (obj["done"] as? Int) == 1 {
            flush()
            if (obj["more"] as? Int) == 1 {
                statusText = "Партію отримано, запитую наступну…"
                BLEManager.shared.send("\u{10}bwsync.start(\(lastSync));\n")
            } else {
                isSyncing = false
                statusText = "Готово. У базі \(AppDatabase.shared.sampleCount) записів"
                BLEManager.shared.log("✅ Синхронізацію завершено")
            }
            return
        }

        guard let t = obj["t"] as? Int else { return }
        pending.append(HealthSample(
            ts: t,
            hr: (obj["hr"] as? Double).flatMap { $0 > 0 ? $0 : nil },
            steps: obj["st"] as? Int,
            movement: obj["mv"] as? Double,
            temperature: obj["tp"] as? Double,
            altitude: obj["al"] as? Double,
            battery: obj["bt"] as? Double,
            activity: obj["ac"] as? String
        ))
        if pending.count >= 50 { flush() }
    }

    private func flush() {
        guard !pending.isEmpty else { return }
        AppDatabase.shared.insert(pending)
        if let maxTs = pending.map(\.ts).max(), maxTs > lastSync { lastSync = maxTs }
        statusText = "У базі \(AppDatabase.shared.sampleCount) записів…"
        pending = []
    }
}
