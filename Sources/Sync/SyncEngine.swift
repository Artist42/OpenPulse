import Foundation

final class SyncEngine: ObservableObject {
    static let shared = SyncEngine()

    @Published var statusText = "Ще не синхронізувалось"
    @Published var isSyncing = false

    private var pending: [HealthSample] = []
    private var watchdog: Timer?

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
        armWatchdog(seconds: 15)
    }

    func resetCursor() { lastSync = 0 }

    private func armWatchdog(seconds: TimeInterval) {
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            guard let self = self, self.isSyncing else { return }
            self.flush()
            self.isSyncing = false
            self.statusText = "Годинник не відповідає. Перевірте bwsync.boot.js і спробуйте ще раз"
        }
    }

    func handleLine(_ line: String) {
        guard line.hasPrefix("BWS:") else { return }
        let json = String(line.dropFirst(4))
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        if obj["ack"] != nil {
            statusText = "Годинник читає історію…"
            armWatchdog(seconds: 120)
            return
        }

        if let p = obj["prog"] as? Int {
            statusText = "Годинник переглянув \(p) записів…"
            armWatchdog(seconds: 120)
            return
        }

        if let err = obj["err"] as? String {
            watchdog?.invalidate()
            isSyncing = false
            statusText = err == "busy" ? "Годинник ще зайнятий, зачекайте хвилину" : "Помилка годинника: \(err)"
            return
        }

        if (obj["done"] as? Int) == 1 {
            flush()
            if (obj["more"] as? Int) == 1 {
                statusText = "Партію отримано, запитую наступну…"
                BLEManager.shared.send("\u{10}bwsync.start(\(lastSync));\n")
                armWatchdog(seconds: 15)
            } else {
                watchdog?.invalidate()
                isSyncing = false
                statusText = "Готово. У базі \(AppDatabase.shared.sampleCount) записів"
                BLEManager.shared.log("✅ Синхронізацію завершено")
            }
            return
        }

        guard let t = obj["t"] as? Int else { return }
        armWatchdog(seconds: 30)
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
