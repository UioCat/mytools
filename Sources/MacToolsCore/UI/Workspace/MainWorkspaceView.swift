// 设置、剪贴板和翻译共用的主工作台容器。
// 负责侧边栏与模块切换，不持久化功能状态。

import SwiftUI

/// 封装 `MainWorkspaceLayout` 在 SwiftUI 展示层中的值语义和相关操作。
public struct MainWorkspaceLayout {
    public static let isSidebarVisibleByDefault = false
    public static let sidebarWidth: CGFloat = 150
    public static let collapsedSidebarToggleSize = MacToolsControlMetrics.toolbarIconSize
    public static let moduleContentHorizontalAlignment = HorizontalAlignment.leading
    public static let moduleContentVerticalAlignment = VerticalAlignment.top
    public static let moduleContentAlignment = Alignment(
        horizontal: moduleContentHorizontalAlignment,
        vertical: moduleContentVerticalAlignment
    )
    public static let animationDuration = 0.18

    /// 创建 `MainWorkspaceLayout`，保存传入依赖并建立初始状态。
    private init() {}
}

/// 描述 `ClipboardSearchFocusPolicy` 在 SwiftUI 展示层中可取的状态、选项或错误。
public enum ClipboardSearchFocusPolicy {
    /// 打开剪贴板模块时递增焦点令牌，其他模块保持原值。
    public static func focusToken(afterOpening module: MainToolModule, currentToken: Int) -> Int {
        module == .clipboard ? currentToken + 1 : currentToken
    }
}

/// SwiftUI 在主 Actor 读取该环境值；其中的闭包只修改视图状态。
public struct MainWorkspaceSidebarChrome: @unchecked Sendable {
    public let isSidebarVisible: Bool
    public let toggleSidebar: () -> Void

    /// 创建 `MainWorkspaceSidebarChrome`，保存传入依赖并建立初始状态。
    public init(isSidebarVisible: Bool, toggleSidebar: @escaping () -> Void) {
        self.isSidebarVisible = isSidebarVisible
        self.toggleSidebar = toggleSidebar
    }
}

/// 封装 `MainWorkspaceSidebarChromeKey` 在 SwiftUI 展示层中的值语义和相关操作。
private struct MainWorkspaceSidebarChromeKey: EnvironmentKey {
    static let defaultValue: MainWorkspaceSidebarChrome? = nil
}

/// 扩展 `EnvironmentValues`，补充本文件所需的 SwiftUI 展示层能力。
public extension EnvironmentValues {
    var mainWorkspaceSidebarChrome: MainWorkspaceSidebarChrome? {
        get { self[MainWorkspaceSidebarChromeKey.self] }
        set { self[MainWorkspaceSidebarChromeKey.self] = newValue }
    }
}

/// 封装 `MainWorkspaceModuleHeader` 在 SwiftUI 展示层中的值语义和相关操作。
public struct MainWorkspaceModuleHeader: View {
    @Environment(\.mainWorkspaceSidebarChrome) private var workspaceSidebarChrome
    private let module: MainToolModule
    private let subtitle: String

    /// 创建 `MainWorkspaceModuleHeader`，保存传入依赖并建立初始状态。
    public init(module: MainToolModule, subtitle: String? = nil) {
        self.module = module
        self.subtitle = subtitle ?? module.subtitle
    }

    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: module.iconName)
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(MacToolsGlassTheme.textSecondary)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(module.title)
                    .font(.system(
                        size: MacToolsControlMetrics.pageTitleFontSize,
                        weight: .medium
                    ))
                    .foregroundStyle(MacToolsGlassTheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MacToolsGlassTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            if let workspaceSidebarChrome {
                sidebarToggleButton(workspaceSidebarChrome)
            }
        }
        .frame(minHeight: MacToolsControlMetrics.pageHeaderMinimumHeight)
        .padding(.horizontal, 16)
        .liquidGlassGroup(spacing: 12)
    }

    /// 构建并返回 `sidebarToggleButton` 对应的 SwiftUI 界面内容或展示状态。
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
        .foregroundStyle(chrome.isSidebarVisible ? MacToolsGlassTheme.textPrimary : MacToolsGlassTheme.textSecondary)
        .liquidGlassButtonStyle(
            cornerRadius: 18,
            isSelected: chrome.isSidebarVisible,
            minimumSize: MainWorkspaceLayout.collapsedSidebarToggleSize
        )
        .help(chrome.isSidebarVisible ? "隐藏工具栏" : "显示工具栏")
    }
}

/// 封装 `MainWorkspaceView` 在 SwiftUI 展示层中的值语义和相关操作。
public struct MainWorkspaceView<SettingsContent: View, ClipboardContent: View, TranslationContent: View>: View {
    @Binding private var selectedModule: MainToolModule
    @State private var isSidebarVisible = MainWorkspaceLayout.isSidebarVisibleByDefault
    private let brandIcon: Image
    private let settingsContent: SettingsContent
    private let clipboardContent: ClipboardContent
    private let translationContent: TranslationContent

    /// 创建 `MainWorkspaceView`，保存传入依赖并建立初始状态。
    public init(
        selectedModule: Binding<MainToolModule>,
        brandIcon: Image,
        @ViewBuilder settings: () -> SettingsContent,
        @ViewBuilder clipboard: () -> ClipboardContent,
        @ViewBuilder translation: () -> TranslationContent
    ) {
        self._selectedModule = selectedModule
        self.brandIcon = brandIcon
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
                    .overlay(MacToolsGlassTheme.divider)
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
        .padding(MacToolsControlMetrics.pagePadding)
        .liquidGlassWindowPanel(frame: .mainWorkspace)
        .animation(.easeInOut(duration: MainWorkspaceLayout.animationDuration), value: isSidebarVisible)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                brandIcon
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34, height: 34)
                    .accessibilityHidden(true)

                Text("MacTools")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(MacToolsGlassTheme.textPrimary)
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 14)

            ForEach(MainToolModule.allCases) { module in
                Button {
                    selectedModule = module
                } label: {
                    Label(module.title, systemImage: module.iconName)
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: MacToolsControlMetrics.sidebarNavigationHeight)
                        .padding(.horizontal, 12)
                        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .foregroundStyle(selectedModule == module ? MacToolsGlassTheme.textPrimary : MacToolsGlassTheme.textSecondary)
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

    /// 切换侧边栏可见性，并由父视图动画响应状态变化。
    private func toggleSidebar() {
        withAnimation(.easeInOut(duration: MainWorkspaceLayout.animationDuration)) {
            isSidebarVisible.toggle()
        }
    }
}
