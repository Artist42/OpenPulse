import CoreBluetooth
import SwiftUI

struct LogLine: Identifiable {
    let id = UUID()
    let date = Date()
    let text: String
}

final class BLEManager: NSObject, ObservableObject {
    static let shared = BLEManager()

    // Nordic UART Service (Bangle.js)
    static let uartServiceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    static let uartRXUUID = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E") // телефон → годинник
    static let uartTXUUID = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E") // годинник → телефон

    @Published var statusText = "Ініціалізація Bluetooth…"
    @Published var isScanning = false
    @Published var isConnected = false
    @Published var discovered: [CBPeripheral] = []
    @Published var logLines: [LogLine] = []

    private var central: CBCentralManager!
    private var watch: CBPeripheral?
    private var rxCharacteristic: CBCharacteristic?
    private var textBuffer = ""

    private override init() {
        super.init()
        central = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionRestoreIdentifierKey: "OpenPulseCentral"]
        )
    }

    private var savedWatchID: UUID? {
        get { UserDefaults.standard.string(forKey: "watchUUID").flatMap(UUID.init) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: "watchUUID") }
    }

    func log(_ text: String) {
        logLines.append(LogLine(text: text))
        if logLines.count > 500 { logLines.removeFirst(logLines.count - 500) }
    }

    func startScan() {
        guard central.state == .poweredOn else { return }
        discovered = []
        isScanning = true
        statusText = "Пошук годинника…"
        central.scanForPeripherals(withServices: nil)
    }

    func stopScan() {
        central.stopScan()
        isScanning = false
    }

    func connect(_ peripheral: CBPeripheral) {
        stopScan()
        savedWatchID = peripheral.identifier
        watch = peripheral
        peripheral.delegate = self
        statusText = "Підключення до \(peripheral.name ?? "годинника")…"
        central.connect(peripheral)
    }

    func reconnectSavedWatch() {
        guard central.state == .poweredOn, let id = savedWatchID else { return }
        if let p = central.retrievePeripherals(withIdentifiers: [id]).first {
            connect(p)
        }
    }

    func forgetWatch() {
        if let watch { central.cancelPeripheralConnection(watch) }
        savedWatchID = nil
        watch = nil
        isConnected = false
        statusText = "Годинник не вибрано"
    }

    func send(_ text: String) {
        guard let watch, let rx = rxCharacteristic,
              let data = text.data(using: .utf8) else {
            log("⚠️ Не можу відправити: канал не готовий")
            return
        }
        let mtu = watch.maximumWriteValueLength(for: .withResponse)
        var offset = 0
        while offset < data.count {
            let chunk = data.subdata(in: offset..<min(offset + mtu, data.count))
            watch.writeValue(chunk, for: rx, type: .withResponse)
            offset += mtu
        }
        log("→ \(text.trimmingCharacters(in: .newlines))")
    }
}

extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if !isConnected { statusText = "Bluetooth готовий" }
            reconnectSavedWatch()
        case .poweredOff: statusText = "Bluetooth вимкнено"
        case .unauthorized: statusText = "Немає дозволу на Bluetooth"
        default: statusText = "Bluetooth недоступний"
        }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        if let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
           let p = restored.first {
            watch = p
            p.delegate = self
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let name = peripheral.name, name.contains("Bangle") else { return }
        if !discovered.contains(where: { $0.identifier == peripheral.identifier }) {
            discovered.append(peripheral)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        isConnected = true
        statusText = "З'єднано з \(peripheral.name ?? "годинником")"
        log("✅ З'єднано з \(peripheral.name ?? "?")")
        peripheral.discoverServices([Self.uartServiceUUID])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        isConnected = false
        statusText = "З'єднання розірвано, чекаю на годинник…"
        log("⚠️ Розрив з'єднання")
        central.connect(peripheral) // iOS сам підключиться, щойно годинник з'явиться поруч
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        statusText = "Не вдалося підключитись, повторюю…"
        central.connect(peripheral)
    }
}

extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.uartServiceUUID }) else { return }
        peripheral.discoverCharacteristics([Self.uartRXUUID, Self.uartTXUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for ch in service.characteristics ?? [] {
            if ch.uuid == Self.uartTXUUID { peripheral.setNotifyValue(true, for: ch) }
            if ch.uuid == Self.uartRXUUID { rxCharacteristic = ch }
        }
        log("🔗 UART готовий")
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error { log("❌ Помилка прийому: \(error.localizedDescription)") }
        log("📦 Прийнято \(characteristic.value?.count ?? 0) байт")
        guard characteristic.uuid == Self.uartTXUUID,
              let data = characteristic.value,
              let text = String(data: data, encoding: .utf8) else { return }
        textBuffer += text
        while let range = textBuffer.range(of: "\n") {
            let line = String(textBuffer[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            textBuffer.removeSubrange(..<range.upperBound)
            guard !line.isEmpty else { continue }
            SyncEngine.shared.handleLine(line)
            if !line.hasPrefix("BWS:{\"t\"") { // окремі записи не спамимо в Журнал
                log("← \(line)")
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            log("❌ Підписка на вхідні дані: \(error.localizedDescription)")
        } else {
            log(characteristic.isNotifying ? "📥 Приймання даних увімкнено" : "📥 Приймання даних вимкнено")
        }
    }
        func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            log("❌ Доставка команди: \(error.localizedDescription)")
        } else {
            log("✓ Команду доставлено")
        }
    }
}
