import MacToolsCore
import SwiftUI

@MainActor
final class MainPanelRouter: ObservableObject {
    @Published var selectedModule: MainToolModule = MainToolModule.defaultModule

    func open(_ module: MainToolModule) {
        selectedModule = module
    }
}

final class PanelDismissHandler {
    var onDismiss: () -> Void = {}

    func dismiss() {
        onDismiss()
    }
}

struct RuntimeMainWorkspaceView: View {
    @ObservedObject var router: MainPanelRouter
    @ObservedObject var model: ClipboardPanelModel
    let settings: AppSettings
    let permissionService: PermissionService
    let onCopy: (ClipboardItem) -> Void
    let onCopyAndPaste: (ClipboardItem) -> Void
    let onDismiss: () -> Void

    var body: some View {
        MainWorkspaceView(selectedModule: $router.selectedModule) {
            RuntimeSettingsView(
                settings: settings,
                permissionService: permissionService,
                presentation: .embedded
            )
        } clipboard: {
            RuntimeClipboardModuleView(
                model: model,
                onCopy: onCopy,
                onCopyAndPaste: onCopyAndPaste,
                onDismiss: onDismiss
            )
        } translation: {
            RuntimeTranslationModuleView()
        }
        .onAppear {
            if router.selectedModule == .clipboard {
                model.prepareForPresentation()
            }
        }
        .onChange(of: router.selectedModule) { module in
            if module == .clipboard {
                model.prepareForPresentation()
            }
        }
    }
}

struct RuntimeClipboardModuleView: View {
    @ObservedObject var model: ClipboardPanelModel
    let onCopy: (ClipboardItem) -> Void
    let onCopyAndPaste: (ClipboardItem) -> Void
    let onDismiss: () -> Void

    var body: some View {
        MainPanelView(
            items: model.items,
            resetToken: model.presentationToken,
            onSelect: { item, action in
                switch action {
                case .copy:
                    onCopy(item)
                case .copyAndPaste:
                    onCopyAndPaste(item)
                }
            },
            onFavoriteToggle: { item in
                model.toggleFavorite(item)
            },
            onDelete: { item in
                model.delete(item)
            },
            onClear: {
                model.clearNonFavorites()
            },
            onDismiss: onDismiss,
            presentation: .embedded
        )
        .onAppear {
            model.refresh()
        }
    }
}

struct RuntimeSettingsView: View {
    let settings: AppSettings
    let permissionService: PermissionService
    let presentation: ToolModulePresentation
    @State private var permissionSummary: PermissionSummary

    init(
        settings: AppSettings,
        permissionService: PermissionService,
        presentation: ToolModulePresentation = .window
    ) {
        self.settings = settings
        self.permissionService = permissionService
        self.presentation = presentation
        self._permissionSummary = State(initialValue: permissionService.summary())
    }

    var body: some View {
        SettingsView(
            settings: settings,
            permissionSummary: permissionSummary,
            openSystemSettings: permissionService.openSystemSettings,
            openPermissionSettings: permissionService.openSystemSettings(for:),
            presentation: presentation
        )
        .onAppear {
            permissionSummary = permissionService.summary()
        }
    }
}

struct RuntimeTranslationModuleView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: MainToolModule.translation.iconName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 38, height: 38)
                    .liquidGlassModule(cornerRadius: 14, isSelected: true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(MainToolModule.translation.title)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.black)
                    Text("翻译模块独立加载，等待服务配置")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.58))
                }
            }
            .padding(14)
            .liquidGlassModule(cornerRadius: 24)

            Text("百度翻译凭证配置完成后，这里会承载翻译模块的独立界面。")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.62))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .liquidGlassModule(cornerRadius: 22)

            Spacer()
        }
        .padding(18)
    }
}
