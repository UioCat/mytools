import MacToolsCore
import SwiftUI

final class PanelDismissHandler {
    var onDismiss: () -> Void = {}

    func dismiss() {
        onDismiss()
    }
}

struct RuntimeMainPanelView: View {
    @ObservedObject var model: ClipboardPanelModel
    let onDismiss: () -> Void

    var body: some View {
        MainPanelView(
            items: model.items,
            onSelect: { item, action in
                model.perform(action, on: item)
            },
            onFavoriteToggle: { item in
                model.toggleFavorite(item)
            },
            onDismiss: onDismiss
        )
        .onAppear {
            model.refresh()
        }
    }
}

struct RuntimeSettingsView: View {
    let settings: AppSettings
    let permissionService: PermissionService
    @State private var permissionSummary: PermissionSummary

    init(settings: AppSettings, permissionService: PermissionService) {
        self.settings = settings
        self.permissionService = permissionService
        self._permissionSummary = State(initialValue: permissionService.summary())
    }

    var body: some View {
        SettingsView(
            settings: settings,
            permissionSummary: permissionSummary,
            openSystemSettings: permissionService.openSystemSettings
        )
        .onAppear {
            permissionSummary = permissionService.summary()
        }
    }
}
