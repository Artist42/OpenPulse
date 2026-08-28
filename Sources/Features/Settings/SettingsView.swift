import SwiftUI
import CoreBluetooth

struct SettingsView: View {
    @EnvironmentObject var ble: BLEManager

    var body: some View {
        NavigationStack {
            List {
                Section("Стан") {
                    HStack {
                        Circle().fill(ble.isConnected ? Color.green : Color.red)
                            .frame(width: 10, height: 10)
                        Text(ble.statusText)
                    }
                }
                Section("Годинник") {
                    if ble.isScanning {
                        HStack { ProgressView(); Text("Пошук…") }
                    }
                    ForEach(ble.discovered, id: \.identifier) { p in
                        Button(p.name ?? "Невідомий пристрій") { ble.connect(p) }
                    }
                    Button(ble.isScanning ? "Зупинити пошук" : "Знайти годинник") {
                        if ble.isScanning { ble.stopScan() } else { ble.startScan() }
                    }
                    Button("Тест зв'язку (ping)") { ble.send("\n") }
                        .disabled(!ble.isConnected)
                    Button("Забути годинник", role: .destructive) { ble.forgetWatch() }
                }
                Section {
                    Text("Перед підключенням повністю закрийте BlueWatch і Web IDE — годинник тримає лише одне з'єднання.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Налаштування")
        }
    }
}
