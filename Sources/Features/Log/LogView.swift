import SwiftUI

struct LogView: View {
    @EnvironmentObject var ble: BLEManager

    var body: some View {
        NavigationStack {
            List(ble.logLines.reversed()) { line in
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.date, style: .time)
                        .font(.caption2).foregroundStyle(.secondary)
                    Text(line.text)
                        .font(.system(.footnote, design: .monospaced))
                }
            }
            .navigationTitle("Журнал")
        }
    }
}
