import SwiftUI

@main
struct OpenPulseApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.fill")
                .font(.system(size: 64))
                .foregroundStyle(.red)
            Text("OpenPulse")
                .font(.largeTitle.bold())
            Text("Каркас працює. Далі — BLE і синхронізація.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
