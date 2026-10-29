import SwiftUI
import Combine

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsManager
    @EnvironmentObject private var account: AccountStore
    @ObservedObject private var player = PlayerService.shared
    @Environment(\.openDestination) private var openDestination
    @State private var category: SettingsCategory = .playback

    private enum SettingsCategory: String, CaseIterable, Identifiable {
        case playback, appearance, lyrics, storage, shortcuts, sync, about

        var id: Self { self }

        var title: String {
            switch self {
            case .playback: return String(localized: "播放")
            case .appearance: return String(localized: "外观")
            case .lyrics: return String(localized: "歌词")
            case .storage: return String(localized: "下载与存储")
            case .shortcuts: return String(localized: "快捷键")
            case .sync: return String(localized: "同步与账户")
            case .about: return String(localized: "关于")
            }
        }

        var icon: String {
            switch self {
            case .playback: return "play.circle"
            case .appearance: return "paintpalette"
            case .lyrics: return "text.quote"
            case .storage: return "internaldrive"
            case .shortcuts: return "keyboard"
            case .sync: return "person.crop.circle"
            case .about: return "info.circle"
            }
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let showsSidebar = geometry.size.width >= 680
            HStack(spacing: 0) {
                if showsSidebar {
                    categorySidebar
                    Divider()
                }

                VStack(spacing: 0) {
                    categoryHeader(showsSidebar: showsSidebar)
                    Divider()
                    categoryContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 420, idealWidth: 760, minHeight: 500, idealHeight: 650)
        .background(SettingsWindowToolbar(onClose: { category = .playback }))
        .overlay(alignment: .top) { SettingsToastOverlay() }
        .noFocusRing()
    }

    private var categorySidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("设置")
                .font(.headline)
                .padding(.horizontal, 10)
                .padding(.top, 6)
                .padding(.bottom, 12)

            ForEach(SettingsCategory.allCases) { item in
                Button {
                    category = item
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: item.icon)
                            .frame(width: 18)
                        Text(item.title)
                        Spacer(minLength: 0)
                    }
                    .font(.body.weight(category == item ? .medium : .regular))
                    .foregroundStyle(category == item ? Theme.accent : .primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                    .background(category == item ? Theme.accent.opacity(0.1) : .clear,
                                in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .noFocusRing()
                .accessibilityAddTraits(category == item ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 172)
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func categoryHeader(showsSidebar: Bool) -> some View {
        HStack {
            if showsSidebar {
                Label(category.title, systemImage: category.icon)
                    .font(.title3.weight(.semibold))
            } else {
                // A menu keeps every category reachable without squeezing a sidebar.
                Picker("设置分类", selection: $category) {
                    ForEach(SettingsCategory.allCases) { item in
                        Label(item.title, systemImage: item.icon).tag(item)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .accessibilityLabel("设置分类")
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(height: 58)
    }

    @ViewBuilder
    private var categoryContent: some View {
        switch category {
        case .playback:
            Form {
                Section("音质") {
                    Picker("播放音质", selection: Binding(
                        get: { account.playbackQuality },
                        set: { PlayerService.shared.setAudioQuality($0) }
                    )) {
                        ForEach(account.availableAudioQualities) { quality in
                            Text(quality.displayName).tag(quality)
                        }
                    }
                    LabeledContent("账号权益", value: account.membershipTier.displayName)
                    if account.isRefreshingMembership {
                        ProgressView().controlSize(.small)
                    } else if account.membershipRefreshFailed {
                        Button("会员信息暂不可用，点击重试") { Task { await account.refreshMembership() } }
                    }
                    if let level = player.servedQuality, let actual = AudioQuality(rawValue: level) {
                        LabeledContent("当前音质", value: actual.displayName)
                    }
                    switch account.membershipTier {
                    case .free: settingsHint("黑胶 VIP 可用无损、Hi-Res 与高清臻音。")
                    case .vip: settingsHint("黑胶 SVIP 可用超清母带与空间音频。")
                    case .svip: settingsHint("实际音质取决于歌曲资源与输出设备。")
                    }
                }
                .task { await account.refreshMembership() }

                Section("AI 调音大师") {
                    Toggle("启用 AI 调音", isOn: Binding(
                        get: { settings.aiSoundEffectEnabled },
                        set: { player.setAISoundEffectEnabled($0) }
                    ))
                    .disabled(account.membershipTier != .svip && !settings.aiSoundEffectEnabled)
                    if account.membershipTier != .svip {
                        settingsHint("需要黑胶 SVIP")
                    } else if settings.aiSoundEffectEnabled {
                        LabeledContent("调音状态", value: player.aiSoundEffectState.displayName)
                        HStack {
                            Text("调音强度")
                            Spacer(minLength: 12)
                            Slider(value: Binding(
                                get: { settings.aiSoundEffectStrength },
                                set: { player.setAISoundEffectStrength($0) }
                            ), in: 0...1, step: 0.05)
                            .frame(maxWidth: 180)
                            .accessibilityLabel("调音强度")
                            Text(settings.aiSoundEffectStrength, format: .percent.precision(.fractionLength(0)))
                                .monospacedDigit()
                                .frame(width: 42, alignment: .trailing)
                        }
                        if player.aiSoundEffectState == .failed {
                            Button("重试调音") { player.refreshAISoundEffect(retry: true) }
                        }
                    }
                    settingsHint("使用官方逐曲均衡曲线，保留源采样率。混响与空间增强暂不支持。")
                    settingsHint("耳机已设置均衡器时，可降低调音强度后对比试听。")
                }
            }
            .formStyle(.grouped)

        case .appearance:
            Form {
                Section("界面") {
                    Picker("主题", selection: $settings.appearance) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Text(appearance.displayName).tag(appearance)
                        }
                    }
                    Picker("播放页模式", selection: $settings.nowPlayingMode) {
                        ForEach(NowPlayingMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                }

                Section("背景") {
                    Toggle("主界面环境色", isOn: $settings.showMainWindowAmbientBackground)
                    if settings.showMainWindowAmbientBackground {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("背景色强度")
                                Spacer()
                                Text("\(Int(settings.mainWindowAmbientBackgroundIntensity * 100))%")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            Slider(
                                value: $settings.mainWindowAmbientBackgroundIntensity,
                                in: SettingsManager.mainWindowAmbientBackgroundIntensityRange,
                                step: 0.1
                            )
                            .accessibilityLabel("背景色强度")
                            HStack {
                                Text("50%")
                                Spacer()
                                Text("150%")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)

        case .lyrics:
            Form {
                Section("歌词显示") {
                    Toggle("显示翻译", isOn: $settings.showLyricsTranslation)
                    Toggle("逐字歌词", isOn: $settings.verbatimLyrics)
                    Picker("日文歌词读音", selection: $settings.lyricsAnnotation) {
                        ForEach(LyricsAnnotation.allCases) { annotation in
                            Text(annotation.displayName).tag(annotation)
                        }
                    }
                    settingsHint("罗马音单独显示一行，汉字读音标在字上方。缺少官方读音时自动生成。")
                }

                Section("桌面歌词") {
                    Toggle("显示桌面歌词", isOn: $settings.showDesktopLyrics)
                    if settings.showDesktopLyrics {
                        Toggle("水平居中", isOn: $settings.desktopLyricsCentered)
                    }
                    settingsHint("歌词悬浮在屏幕上，可拖动调整位置。")
                }
            }
            .formStyle(.grouped)

        case .storage:
            StorageSpaceView {
                openDestination(.downloaded)
            }

        case .shortcuts:
            ShortcutSettingsView()

        case .sync:
            Form {
                SyncSettingsSection()

                Section("账户") {
                    if let profile = account.profile {
                        LabeledContent("当前账户", value: profile.nickname)
                        Button("退出登录", role: .destructive) {
                            Task {
                                do { try await AccountStore.shared.logout() }
                                catch { ToastCenter.shared.show(error.localizedDescription) }
                            }
                        }
                    } else {
                        Text("未登录")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

        case .about:
            Form {
                Section("Liltiva") {
                    LabeledContent("版本", value: appVersion)
                    settingsHint("网易云音乐第三方客户端。数据来自网易云音乐。")
                }
            }
            .formStyle(.grouped)
        }
    }

    private func settingsHint(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }
}

private struct SettingsToastOverlay: View {
    @ObservedObject private var toasts = ToastCenter.shared

    var body: some View {
        Group {
            if let toast = toasts.current {
                ToastView(toast: toast)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 12)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .animation(.spring(duration: 0.3), value: toasts.current)
        .allowsHitTesting(false)
    }
}

/// Keep the settings titlebar compact and reset the category after closing.
struct SettingsWindowToolbar: NSViewRepresentable {
    let onClose: () -> Void

    func makeNSView(context: Context) -> ToolbarHost {
        let view = ToolbarHost()
        view.onClose = onClose
        return view
    }

    func updateNSView(_ nsView: ToolbarHost, context: Context) {
        nsView.onClose = onClose
        nsView.updateToolbar()
    }

    final class ToolbarHost: NSView {
        var onClose: () -> Void = {}
        private var closeObserver: AnyCancellable?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            closeObserver = window.map { window in
                NotificationCenter.default.publisher(for: NSWindow.willCloseNotification, object: window)
                    .sink { [weak self] _ in self?.onClose() }
            }
            updateToolbar()
            DispatchQueue.main.async { [weak self] in
                self?.window?.clearAutoFocusIfNeeded()
            }
        }

        func updateToolbar() {
            DispatchQueue.main.async { [weak self] in
                guard let window = self?.window else { return }
                if window.toolbarStyle != .unifiedCompact || !window.styleMask.contains(.resizable) {
                    // Settings scenes omit the resize handle even with contentMinSize.
                    // Enable it here so the category layout can follow the window width.
                    window.styleMask.insert(.resizable)
                    window.toolbarStyle = .unifiedCompact
                }
                window.contentView?.disableFocusRingsRecursively()
            }
        }
    }
}
