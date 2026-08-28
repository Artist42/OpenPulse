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

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 56)).foregroundStyle(.red)
                Text(ble.isConnected ? "Годинник підключено" : "Годинник не підключено")
                    .font(.headline)
                Text("Дані з'являться тут після Етапу 4 (синхронізація історії).")
                    .font(.footnote).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .navigationTitle("Сьогодні")
        }
    }
}
