import SwiftUI

@main
struct OpenPulseApp: App {
    @StateObject private var ble = BLEManager.shared

    var body: some Scene {
        WindowGroup {
            TabView {
                TodayView()
                    .tabItem { Label("Сьогодні", systemImage: "heart.text.square") }
                LogView()
                    .tabItem { Label("Журнал", systemImage: "terminal") }
                SettingsView()
                    .tabItem { Label("Налаштування", systemImage: "gearshape") }
            }
            .environmentObject(ble)
        }
    }
}

struct TodayView: View {
    @EnvironmentObject var ble: BLEManager
    @ObservedObject var db = AppDatabase.shared
    @ObservedObject var sync = SyncEngine.shared

    var body: some View {
        NavigationStack {
            List {
                Section("Годинник") {
                    HStack {
                        Circle()
                            .fill(ble.isConnected ? Color.green : Color.red)
                            .frame(width: 10, height: 10)
                        Text(ble.statusText)
                    }
                }

                Section("База даних") {
                    HStack {
                        Text("Записів")
                        Spacer()
                        Text("\(db.sampleCount)").bold()
                    }
                    HStack {
                        Text("Останній запис")
                        Spacer()
                        Text(db.lastSampleDate.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "—")
                            .foregroundStyle(.secondary)
                    }
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

                    Button("Повний ресинк (з нуля)", role: .destructive) {
                        sync.resetCursor()
                        sync.startSync()
                    }
                    .disabled(sync.isSyncing || !ble.isConnected)
                }
            }
            .navigationTitle("Сьогодні")
        }
    }
}
