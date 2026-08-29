import SwiftUI

@main
struct OpenPulseApp: App {
    @StateObject private var ble = BLEManager.shared

    var body: some Scene {
        WindowGroup {
            TabView {
                TodayView()
                    .tabItem { Label("Сьогодні", systemImage: "heart.text.square") }
                SleepView()
                    .tabItem { Label("Сон", systemImage: "moon.zzz.fill") }
                HeartRateView()
                    .tabItem { Label("Пульс", systemImage: "heart.fill") }
                ActivityView()
                    .tabItem { Label("Активність", systemImage: "figure.walk") }
                LogView()
                    .tabItem { Label("Журнал", systemImage: "terminal") }
                SettingsView()
                    .tabItem { Label("Налаштування", systemImage: "gearshape") }
            }
            .environmentObject(ble)
        }
    }
}
