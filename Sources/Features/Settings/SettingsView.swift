import SwiftUI
import CoreBluetooth

struct SettingsView: View {
    @EnvironmentObject var ble: BLEManager
    @ObservedObject var sync = SyncEngine.shared
    @State private var showWipeConfirm = false

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
                Section("Синхронізація") {
                    Text(sync.statusText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button {
                        sync.startSync()
                    } label: {
                        if sync.isSyncing {
                            ProgressView()
                        } else {
                            Text("Синхронізувати зараз")
                        }
                    }
                    .disabled(sync.isSyncing || !ble.isConnected)

                    Button("Повний ресинк (стерти базу)", role: .destructive) {
                        showWipeConfirm = true
                    }
                    .disabled(sync.isSyncing || !ble.isConnected)
                }
                Section {
                    Text("Перед підключенням повністю закрийте BlueWatch і Web IDE — годинник тримає лише одне з'єднання.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Налаштування")
            .confirmationDialog(
                "Ви впевнені, що хочете видалити всі існуючі дані?",
                isPresented: $showWipeConfirm,
                titleVisibility: .visible
            ) {
                Button("Так, стерти і ресинкнути", role: .destructive) {
                    AppDatabase.shared.wipeAll()
                    sync.resetCursor()
                    sync.startSync()
                }
                Button("Скасувати", role: .cancel) {}
            } message: {
                Text("Історія зітреться з бази застосунку і завантажиться з годинника заново. Годинник зберігає лише останні ~45 днів.")
            }
        }
    }
}
