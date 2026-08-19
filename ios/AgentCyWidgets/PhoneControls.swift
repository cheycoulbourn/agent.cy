import AppIntents
import SwiftUI
import WidgetKit

struct VoiceSparkControlWidget: ControlWidget {
    static let kind = "com.agentcy.control.voice-spark"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenVoiceSparkIntent()) {
                Label("Voice Spark", systemImage: "mic.fill")
            }
        }
        .displayName("Voice Spark")
        .description("Record a thought in agent.cy.")
    }
}
