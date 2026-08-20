// 收藏标签的轻量多选与创建 Popover。
// 只管理编辑草稿，持久化动作通过调用方闭包提交。

import SwiftUI

/// 在剪贴板行内编辑多个收藏标签，不引入独立管理页面。
struct ClipboardTagEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTags: [String]
    @State private var newTag = ""

    private let availableTags: [String]
    private let onSave: ([String]) -> Void

    init(
        availableTags: [String],
        initialTags: [String],
        onSave: @escaping ([String]) -> Void
    ) {
        let selectedTags = ClipboardTagPolicy.normalized(initialTags)
        self.availableTags = ClipboardTagPolicy.normalizedCatalog(availableTags + selectedTags)
        self.onSave = onSave
        _selectedTags = State(initialValue: selectedTags)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("收藏标签")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MacToolsGlassTheme.textPrimary)

            if displayedTags.isEmpty {
                Text("还没有标签，可在下方新建")
                    .font(.system(size: 12))
                    .foregroundStyle(MacToolsGlassTheme.textTertiary)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(displayedTags, id: \.self) { tag in
                            tagOption(tag)
                        }
                    }
                }
                .frame(maxHeight: 160)
            }

            HStack(spacing: 8) {
                TextField("新建标签", text: $newTag)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addNewTag)

                Button("添加", action: addNewTag)
                    .disabled(normalizedNewTag == nil || selectedTags.count >= ClipboardTagPolicy.maximumTagCount)
            }

            HStack {
                Text("最多 \(ClipboardTagPolicy.maximumTagCount) 个标签")
                    .font(.system(size: 10))
                    .foregroundStyle(MacToolsGlassTheme.textTertiary)

                Spacer()

                Button("取消") {
                    dismiss()
                }

                Button("保存") {
                    onSave(ClipboardTagPolicy.normalized(selectedTags))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 300)
    }

    /// 构建一个可多选的既有标签行。
    private func tagOption(_ tag: String) -> some View {
        let isSelected = ClipboardTagPolicy.contains(tag, in: selectedTags)
        return Button {
            if isSelected {
                selectedTags.removeAll { ClipboardTagPolicy.contains(tag, in: [$0]) }
            } else if selectedTags.count < ClipboardTagPolicy.maximumTagCount {
                selectedTags = ClipboardTagPolicy.normalized(selectedTags + [tag])
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(
                        isSelected ? MacToolsGlassTheme.selectionBlue : MacToolsGlassTheme.textTertiary
                    )
                Text(tag)
                    .foregroundStyle(MacToolsGlassTheme.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var normalizedNewTag: String? {
        ClipboardTagPolicy.normalized([newTag]).first
    }

    private var displayedTags: [String] {
        ClipboardTagPolicy.normalizedCatalog(availableTags + selectedTags)
    }

    private func addNewTag() {
        guard let normalizedNewTag,
              selectedTags.count < ClipboardTagPolicy.maximumTagCount else {
            return
        }
        selectedTags = ClipboardTagPolicy.normalized(selectedTags + [normalizedNewTag])
        newTag = ""
    }
}
