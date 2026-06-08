import SwiftUI

public struct MainWorkspaceLayout {
    public static let isSidebarVisibleByDefault = false
    public static let sidebarWidth: CGFloat = 150
    public static let collapsedSidebarToggleSize = CGSize(width: 48, height: 48)
    public static let moduleContentHorizontalAlignment = HorizontalAlignment.leading
    public static let moduleContentVerticalAlignment = VerticalAlignment.top
    public static let moduleContentAlignment = Alignment(
        horizontal: moduleContentHorizontalAlignment,
        vertical: moduleContentVerticalAlignment
    )
    public static let animationDuration = 0.18

    private init() {}
}

public enum ClipboardSearchFocusPolicy {
    public static func focusToken(afterOpening module: MainToolModule, currentToken: Int) -> Int {
        module == .clipboard ? currentToken + 1 : currentToken
    }
}

public struct MainWorkspaceSidebarChrome {
    public let isSidebarVisible: Bool
    public let toggleSidebar: () -> Void

    public init(isSidebarVisible: Bool, toggleSidebar: @escaping () -> Void) {
        self.isSidebarVisible = isSidebarVisible
        self.toggleSidebar = toggleSidebar
    }
}

private struct MainWorkspaceSidebarChromeKey: EnvironmentKey {
    static let defaultValue: MainWorkspaceSidebarChrome? = nil
}

public extension EnvironmentValues {
    var mainWorkspaceSidebarChrome: MainWorkspaceSidebarChrome? {
        get { self[MainWorkspaceSidebarChromeKey.self] }
        set { self[MainWorkspaceSidebarChromeKey.self] = newValue }
    }
}

public struct MainWorkspaceModuleHeader: View {
    @Environment(\.mainWorkspaceSidebarChrome) private var workspaceSidebarChrome
    private let module: MainToolModule
    private let subtitle: String

    public init(module: MainToolModule, subtitle: String? = nil) {
        self.module = module
        self.subtitle = subtitle ?? module.subtitle
    }

    public var body: some View {
        HStack(spacing: 12) {
            if let workspaceSidebarChrome {
                sidebarToggleButton(workspaceSidebarChrome)
            }

            Image(systemName: module.iconName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 38, height: 38)
                .liquidGlassModule(cornerRadius: 14, isSelected: true)

            VStack(alignment: .leading, spacing: 2) {
                Text(module.title)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.black)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.58))
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(14)
        .liquidGlassModule(cornerRadius: 24)
        .liquidGlassGroup(spacing: 12)
    }

    private func sidebarToggleButton(_ chrome: MainWorkspaceSidebarChrome) -> some View {
        Button {
            chrome.toggleSidebar()
        } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 16, weight: .semibold))
                .frame(
                    width: MainWorkspaceLayout.collapsedSidebarToggleSize.width,
                    height: MainWorkspaceLayout.collapsedSidebarToggleSize.height
                )
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .foregroundStyle(chrome.isSidebarVisible ? Color.black : Color.black.opacity(0.78))
        .liquidGlassButtonStyle(
            cornerRadius: 18,
            isSelected: chrome.isSidebarVisible,
            minimumSize: MainWorkspaceLayout.collapsedSidebarToggleSize
        )
        .help(chrome.isSidebarVisible ? "隐藏工具栏" : "显示工具栏")
    }
}

public struct MainWorkspaceView<SettingsContent: View, ClipboardContent: View, TranslationContent: View>: View {
    @Binding private var selectedModule: MainToolModule
    @State private var isSidebarVisible = MainWorkspaceLayout.isSidebarVisibleByDefault
    private let settingsContent: SettingsContent
    private let clipboardContent: ClipboardContent
    private let translationContent: TranslationContent

    public init(
        selectedModule: Binding<MainToolModule>,
        @ViewBuilder settings: () -> SettingsContent,
        @ViewBuilder clipboard: () -> ClipboardContent,
        @ViewBuilder translation: () -> TranslationContent
    ) {
        self._selectedModule = selectedModule
        self.settingsContent = settings()
        self.clipboardContent = clipboard()
        self.translationContent = translation()
    }

    public var body: some View {
        HStack(spacing: 0) {
            if isSidebarVisible {
                sidebar
                    .transition(.move(edge: .leading).combined(with: .opacity))

                Divider()
                    .overlay(Color.black.opacity(0.10))
                    .padding(.vertical, 12)
                    .transition(.opacity)
            }

            moduleContent
                .environment(
                    \.mainWorkspaceSidebarChrome,
                    MainWorkspaceSidebarChrome(
                        isSidebarVisible: isSidebarVisible,
                        toggleSidebar: toggleSidebar
                    )
                )
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: MainWorkspaceLayout.moduleContentAlignment
                )
        }
        .liquidGlassGroup(spacing: 18)
        .padding(18)
        .liquidGlassWindowPanel(frame: .mainWorkspace)
        .animation(.easeInOut(duration: MainWorkspaceLayout.animationDuration), value: isSidebarVisible)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(MainToolModule.allCases) { module in
                Button {
                    selectedModule = module
                } label: {
                    Label(module.title, systemImage: module.iconName)
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 42)
                        .padding(.horizontal, 12)
                        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .foregroundStyle(selectedModule == module ? Color.black : Color.black.opacity(0.76))
                .liquidGlassButtonStyle(cornerRadius: 16, isSelected: selectedModule == module)
            }

            Spacer(minLength: 0)
        }
        .liquidGlassGroup(spacing: 10)
        .frame(width: MainWorkspaceLayout.sidebarWidth)
        .padding(.trailing, 16)
    }

    @ViewBuilder
    private var moduleContent: some View {
        switch selectedModule {
        case .settings:
            settingsContent
        case .clipboard:
            clipboardContent
        case .translation:
            translationContent
        }
    }

    private func toggleSidebar() {
        withAnimation(.easeInOut(duration: MainWorkspaceLayout.animationDuration)) {
            isSidebarVisible.toggle()
        }
    }
}
