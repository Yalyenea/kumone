import SwiftUI

struct AutoMixSettingsSection: View {
    @EnvironmentObject private var settings: SettingsManager

    var body: some View {
        Section("AutoMix") {
            Toggle("AutoMix", isOn: $settings.automixEnabled)
            Text("让歌曲丝滑衔接，让听感更流畅")
                .font(.caption)
                .foregroundStyle(.secondary)
            if settings.automixEnabled {
                Toggle("自动过渡", isOn: $settings.automixTransitionsEnabled)
                Toggle(isOn: $settings.automixOrderEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("智能顺序")
                        Text("按歌曲契合度排序，会增加网络用量。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityLabel("智能顺序")
                .accessibilityHint("按歌曲契合度排序，会增加网络用量。")
                Toggle("响度均衡", isOn: $settings.loudnessCompensationEnabled)
            }
        }
    }
}
