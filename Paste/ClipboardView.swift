// ClipboardView.swift

import AppKit
import SwiftUI
import Combine
import Accessibility
import UniformTypeIdentifiers

struct ClipboardView: View {
    @ObservedObject var model: ClipboardHistoryModel
    @Binding var selectedCategory: String
    @Binding var showingTagDialog: Bool
    @Binding var currentItem: ClipboardItem?
    @Binding var newTag: String
    @Binding var selectedItems: Set<ClipboardItem> // Changed from selectedItem
    @State private var showingPopup: Bool = false

    private let itemWidth: CGFloat = 250

    @State private var showingAddCategoryDialog = false

    var body: some View {
        VStack(spacing: 8) {
            categoryScrollView
            if model.filteredItems.isEmpty {
                noDataView
            } else {
                clipboardItemsScrollView
            }
        }
        .padding(8)
        .onTapGesture {
            // 点击空白区域，清除所有选中的项目
            selectedItems.removeAll()
        }
        .onReceive(model.$filteredItems) { items in
            print("UI received filteredItems count: \(items.count)")
        }
    }

    private var clipboardItemsScrollView: some View {
        ScrollViewReader { scrollViewProxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(model.filteredItems) { item in
                        ClipboardItemView(
                            item: item,
                            showingTagDialog: $showingTagDialog,
                            currentItem: $currentItem,
                            selectedItems: $selectedItems, // Changed from selectedItem
                            showingPopup: $showingPopup
                        )
                        .frame(width: itemWidth)
                        .id(item.id)
                        .onAppear {
                            if item == model.filteredItems.last && !model.isSearchingAllData {
                                model.loadMoreItems()
                            }
                        }
                    }
                    // Loading Indicator
                    if model.isLoading && model.hasMoreItems {
                        ProgressView()
                            .frame(width: itemWidth, height: 200)
                    }
                }
                .padding(.horizontal, 4)
            }
            .frame(maxHeight: 200)
            .onChange(of: selectedItems) { _ in
                if let firstSelectedItem = selectedItems.first {
                    withAnimation {
                        scrollViewProxy.scrollTo(firstSelectedItem.id, anchor: .center)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SpacebarPressed"))) { _ in
                if let firstSelectedItem = selectedItems.first {
                    withAnimation {
                        scrollViewProxy.scrollTo(firstSelectedItem.id, anchor: .center)
                    }
                    showingPopup.toggle()
                }
            }
        }
    }

    private var noDataView: some View {
            VStack {
                if let error = model.searchError {
                    // Error view
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 50))
                            .foregroundColor(.red)
                        Text("Search Error")
                            .font(.headline)
                            .foregroundColor(.red)
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        Button("Try Regular Search") {
                            model.applyRegularSearch()
                        }
                        .padding(.top)
                    }
                } else if model.selectedCategory.lowercased() == "ai" && model.searchText.isEmpty {
                    Text("Enter a search term to perform AI search")
                        .font(.headline)
                        .foregroundColor(.gray)
                } else {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 50))
                        .foregroundColor(.gray)
                    Text("No data found")
                        .font(.headline)
                        .foregroundColor(.gray)
                    if !model.isSearchingAllData && !model.searchText.isEmpty {
                        Button("Search All Data") {
                            model.isSearchingAllData = true
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }

    private var categoryScrollView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 8) {
                ForEach(model.categories, id: \.self) { category in
                    CategoryButton(
                        category: category,
                        selectedCategory: $selectedCategory,
                        action: {
                            selectedCategory = category
                            model.selectedCategory = category
                            if category == "Clipboard History" {
                                model.loadInitialItems()
                            }
                        },
                        deleteAction: {
                            model.deleteEntireTag(category)
                        },
                        renameAction: { newName in
                            model.renameTag(oldTag: category, newTag: newName)
                        },
                        model: model
                    )
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(height: 30)
    }
}

struct CategoryButton: View {
    let category: String
    @Binding var selectedCategory: String
    let action: () -> Void
    let deleteAction: (() -> Void)?
    let renameAction: ((String) -> Void)?
    @ObservedObject var model: ClipboardHistoryModel

    @State private var isEditing = false
    @State private var isDragging = false
    @State private var editedCategory: String
    @FocusState private var isTextFieldFocused: Bool

    // 新增：用于定义 AI 标签的样式常量
    private struct AIStyle {
        static let gradientColors = [
            Color(red: 0.4, green: 0.2, blue: 0.8),  // 深紫色
            Color(red: 0.2, green: 0.3, blue: 0.9)   // 深蓝色
        ]
        static let shadowColor = Color(red: 0.4, green: 0.2, blue: 0.8)
        static let iconName = "brain.head.profile"
    }

    init(category: String,
         selectedCategory: Binding<String>,
         action: @escaping () -> Void,
         deleteAction: (() -> Void)? = nil,
         renameAction: ((String) -> Void)? = nil,
         model: ClipboardHistoryModel) {
        self.category = category
        self._selectedCategory = selectedCategory
        self.action = action
        self.deleteAction = deleteAction
        self.renameAction = renameAction
        self.model = model
        self._editedCategory = State(initialValue: category)
    }

    var body: some View {
        Group {
            if isEditing {
                editingView
            } else {
                categoryButton
            }
        }
    }

    // MARK: - 编辑模式视图
    private var editingView: some View {
        TextField("", text: $editedCategory, onCommit: commitEdit)
            .textFieldStyle(PlainTextFieldStyle())
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))
            .foregroundColor(.primary)
            .cornerRadius(15)
            .focused($isTextFieldFocused)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.isTextFieldFocused = true
                }
            }
    }

    // MARK: - 常规按钮视图
    private var categoryButton: some View {
        Button(action: {
            selectedCategory = category
            action()
        }) {
            HStack(spacing: 2) { // 将spacing从4改为2，让图标和文字更靠近
                // AI 标签图标
                if category == "AI" {
                    Image(systemName: AIStyle.iconName)
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                }
                
                // 标签文本
                Text(category)
                    .lineLimit(1)
                    .padding(.leading, category == "AI" ? 2 : 12) // 当有图标时左边距改小
                    .padding(.trailing, 12)
                    .padding(.vertical, 6)
            }
            .padding(.leading, category == "AI" ? 10 : 0) // 整体左边距，只在AI标签时添加
            .background(backgroundView)
            .foregroundColor(foregroundColor)
            .cornerRadius(15)
            .shadow(
                color: shadowColor,
                radius: category == "AI" ? 4 : 0
            )
        }
        .buttonStyle(PlainButtonStyle())
        // 拖拽功能
        .onDrag {
            self.isDragging = true
            return NSItemProvider(object: category as NSString)
        }
        .onDrop(of: [UTType.text], delegate: CategoryDropDelegate(
            category: category,
            categories: $model.categories,
            isDragging: $isDragging
        ))
        // 双击编辑
        .onTapGesture(count: 2) {
            if category != "Clipboard History" && category != "AI" {
                self.editedCategory = category
                isEditing = true
            }
        }
        // 上下文菜单
        .contextMenu {
            if category != "Clipboard History" && category != "AI" {
                Button("Delete Tag") {
                    deleteAction?()
                }
                Button("Rename Tag") {
                    self.editedCategory = category
                    isEditing = true
                }
            }
        }
    }

    // MARK: - 辅助视图和颜色计算
    @ViewBuilder
    private var backgroundView: some View {
        if category == "AI" {
            LinearGradient(
                gradient: Gradient(colors: AIStyle.gradientColors),
                startPoint: .leading,
                endPoint: .trailing
            )
        } else {
            selectedCategory == category ? Color.accentColor : Color(NSColor.controlBackgroundColor)
        }
    }

    private var foregroundColor: Color {
        if category == "AI" {
            return .white
        }
        return selectedCategory == category ? .white : .primary
    }

    private var shadowColor: Color {
        category == "AI" ? AIStyle.shadowColor.opacity(0.3) : .clear
    }

    // MARK: - 功能方法
    private func commitEdit() {
        isEditing = false
        if editedCategory != category && !editedCategory.isEmpty {
            renameAction?(editedCategory)
        }
    }
}

// MARK: - 预览
#Preview {
    HStack {
        CategoryButton(
            category: "AI",
            selectedCategory: .constant("AI"),
            action: {},
            model: ClipboardHistoryModel()
        )
        CategoryButton(
            category: "Clipboard History",
            selectedCategory: .constant("AI"),
            action: {},
            model: ClipboardHistoryModel()
        )
        CategoryButton(
            category: "Custom Tag",
            selectedCategory: .constant("AI"),
            action: {},
            deleteAction: {},
            renameAction: { _ in },
            model: ClipboardHistoryModel()
        )
    }
    .padding()
}

struct ClipboardItemView: View {
    let item: ClipboardItem
    @Binding var showingTagDialog: Bool
    @Binding var currentItem: ClipboardItem?
    @Binding var selectedItems: Set<ClipboardItem>
    @Binding var showingPopup: Bool
    @EnvironmentObject var model: ClipboardHistoryModel

    @State private var nsImage: NSImage? = nil
    @State private var isShowingPopover = false
    @State private var localIsSelected = false // Add local state for tracking selection
    @State private var isContextMenuActive = false // Add state for tracking context menu

    private var isSelected: Bool {
        selectedItems.contains(item)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            itemHeader
            itemContent
            itemTags
            itemFooter
        }
        .padding(6)
       .background(Color(NSColor.controlBackgroundColor))
       .overlay(
           RoundedRectangle(cornerRadius: 8)
               .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
       )
       .cornerRadius(8)
       .contentShape(Rectangle())
       .onTapGesture {
           handleSelection()
       }
       .gesture(
           TapGesture(count: 2)
               .onEnded {
                   copySelectedItemsToClipboard()
               }
       )
       .simultaneousGesture(
           // 使用 simultaneousGesture 来处理右键点击
           TapGesture()
               .modifiers(.control)
               .onEnded { _ in
                   handleSelection(forceSelect: true)
               }
       )
        
         .onChange(of: isContextMenuActive) { active in
             if active {
                 handleSelection(forceSelect: true)
             }
         }
       .contextMenu {
           Group {
               if let previousApp = AppStateManager.shared.previousApp {
                   Button("Paste to \(previousApp.localizedName ?? "App")") {
                       pasteItem(to: previousApp)
                   }
               }
               
               // 确保显示正确的复制数量
               let copyCount = selectedItems.contains(item) ? selectedItems.count : 1
               Button("Copy (\(copyCount) items)") {
                   if !selectedItems.contains(item) {
                       selectedItems = [item]
                   }
                   copySelectedItemsToClipboard()
                   NotificationCenter.default.post(name: NSNotification.Name("RestoreFocus"), object: nil)
               }
               
               Divider()
               
               Button("Add Tag") {
                   currentItem = item
                   showingTagDialog = true
               }
               
               Button("Set Reminder") {
                   //addReminderWithAppleScript(title: "remind from paste", note:item.content)
                   ReminderService.shared.addReminder(content: item.content)
               }

               Divider()
               
               if selectedItems.contains(item) && selectedItems.count > 1 {
                   Button("Delete (\(selectedItems.count) items)") {
                       for selectedItem in selectedItems {
                           model.deleteClipboardItem(selectedItem)
                       }
                       selectedItems.removeAll()
                       NotificationCenter.default.post(name: NSNotification.Name("RestoreFocus"), object: nil)
                   }
               } else {
                   Button("Delete") {
                       model.deleteClipboardItem(item)
                       selectedItems.removeAll()
                       NotificationCenter.default.post(name: NSNotification.Name("RestoreFocus"), object: nil)
                   }
               }
           }
       }
        .popover(isPresented: $isShowingPopover, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
            VStack {
                if item.type == "Text" {
                    LargeTextViewWithSearch(text: item.content)
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if item.type == "Image", let imageData = item.imageData, let image = NSImage(data: imageData) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding()
                } else {
                    Text("No content")
                        .padding()
                }
            }
            .frame(width: 600, height: 400)
        }
        .onChange(of: isShowingPopover) { newValue in
            if !newValue {
                // Popover dismissed, restore focus to the scroll view
                DispatchQueue.main.async {
                    NSApp.keyWindow?.makeFirstResponder(nil)
                }
            }
        }
        // Handle selection and gestures
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SpacebarPressed"))) { _ in
            if isSelected {
                isShowingPopover.toggle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("DismissPopover"))) { _ in
            if isShowingPopover {
                isShowingPopover = false
            }
        }
        .onDisappear {
            isShowingPopover = false
            if selectedItems.contains(item) {
                showingPopup = false
            }
        }


    }

    private func handleSelection(forceSelect: Bool = false) {
        DispatchQueue.main.async {
            if NSEvent.modifierFlags.contains(.command) && !forceSelect {
                // Command + Click 多选
                if selectedItems.contains(item) {
                    selectedItems.remove(item)
                } else {
                    selectedItems.insert(item)
                }
            } else {
                // 单选或强制选择
                if forceSelect || selectedItems.isEmpty || !selectedItems.contains(item) {
                    selectedItems = [item]
                }
            }
            // 发送选择通知
            NotificationCenter.default.post(name: Notification.Name("ItemSelected"), object: nil)
        }
    }

    private func copySelectedItemsToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        var itemsToCopy: [NSPasteboardItem] = []

        for item in selectedItems {
            let pasteboardItem = NSPasteboardItem()
            switch item.type {
            case "Text":
                pasteboardItem.setString(item.content, forType: .string)
            case "Image":
                if let imageData = item.imageData {
                    pasteboardItem.setData(imageData, forType: .tiff)
                }
            default:
                break
            }
            itemsToCopy.append(pasteboardItem)
        }
        pasteboard.writeObjects(itemsToCopy)
        print("Copied \(selectedItems.count) items to clipboard.")
    }

    private func pasteItem(to app: NSRunningApplication) {
        copySelectedItemsToClipboard()
        app.activate(options: .activateIgnoringOtherApps)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if AXIsProcessTrusted() {
                let cmdVDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: true)
                cmdVDown?.flags = .maskCommand
                let cmdVUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: false)
                cmdVUp?.flags = .maskCommand

                cmdVDown?.post(tap: .cghidEventTap)
                cmdVUp?.post(tap: .cghidEventTap)
            } else {
                let alert = NSAlert()
                alert.messageText = "Accessibility Permissions Required"
                alert.informativeText = "Please enable accessibility permissions for this app in System Preferences under Security & Privacy > Privacy > Accessibility."
                alert.runModal()
            }
        }
    }

    private var itemHeader: some View {
        HStack {
            if let appIcon = getAppIcon(for: item.source) {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 16, height: 16)
            }
            Text(item.type)
                .font(.caption)
                .lineLimit(1)
            if item.type == "Text" && isLikelyCode(item.content) {
                Text("Code")
                    .font(.caption)
                    .padding(2)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(4)
            }
            Spacer()
            Text(item.timestamp.timeAgoString())
                .font(.caption2)
        }
    }

    private var itemContent: some View {
        Group {
            if item.type == "Image" {
                itemImageContent
            } else {
                itemTextContent
            }
        }
        .frame(height: 80)
    }

    private var itemTextContent: some View {
        Text(item.content)
            .font(.system(size: 14))
            .lineLimit(4)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var itemImageContent: some View {
        if let image = nsImage {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        } else if let imageData = item.imageData,
                  let image = NSImage(data: imageData) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .onAppear {
                    self.nsImage = image
                }
        } else {
            VStack {
                Image(systemName: "photo.fill.xmark")
                    .font(.system(size: 30))
                    .foregroundColor(.red)
                Text("Unable to load image")
                    .font(.caption)
                    .foregroundColor(.red)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var itemTags: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 4) {
                ForEach(Array(item.tags), id: \.self) { tag in
                    TagView(tag: tag, item: item)
                }
            }
        }
        .frame(height: 18)
    }

    private var itemFooter: some View {
        Group {
            if item.type == "Text" {
                Text("\(item.content.count) characters")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func isLikelyCode(_ text: String) -> Bool {
        let codeIndicators = [
            "func ", "var ", "let ", "class ", "struct ", "enum ", // Swift
            "def ", "class ", "import ", "from ", "if __name__", // Python
            "function ", "var ", "const ", "let ", "class ", // JavaScript
            "public class ", "private ", "protected ", "import ", // Java
            "#include ", "int ", "void ", "char ", "float ", // C/C++
            "<?php", "namespace ", "use ", // PHP
        ]

        let lines = text.components(separatedBy: .newlines)
        let nonEmptyLines = lines.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        // Check if more than 30% of non-empty lines start with common code indicators
        let codeLineCount = nonEmptyLines.filter { line in
            codeIndicators.contains { line.trimmingCharacters(in: .whitespaces).hasPrefix($0) }
        }.count

        let codeLineRatio = Double(codeLineCount) / Double(nonEmptyLines.count)

        // Check for common code patterns
        let containsBraces = text.contains("{") && text.contains("}")
        let containsParentheses = text.contains("(") && text.contains(")")
        let containsSemicolons = text.contains(";")
        let containsIndentation = nonEmptyLines.contains { $0.hasPrefix(" ") || $0.hasPrefix("\t") }

        return codeLineRatio > 0.3 || (containsBraces && containsParentheses) || (containsSemicolons && containsIndentation)
    }

    private func getAppIcon(for bundleIdentifier: String) -> NSImage? {
        if let cachedIcon = ClipboardItemView.appIconCache[bundleIdentifier] {
            return cachedIcon
        }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return nil
        }
        let appIcon = NSWorkspace.shared.icon(forFile: appURL.path)
        ClipboardItemView.appIconCache[bundleIdentifier] = appIcon
        return appIcon
    }

    static var appIconCache = [String: NSImage]()
}

struct TagView: View {
    @State private var isEditing = false
    @State private var editedTag: String
    let tag: String
    let item: ClipboardItem

    @EnvironmentObject var model: ClipboardHistoryModel

    @FocusState private var isTextFieldFocused: Bool

    init(tag: String, item: ClipboardItem) {
        self.tag = tag
        self.item = item
        self._editedTag = State(initialValue: tag)
    }

    var body: some View {
        HStack(spacing: 2) {
            if isEditing {
                TextField("", text: $editedTag, onCommit: commitEdit)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 12))
                    .focused($isTextFieldFocused)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            self.isTextFieldFocused = true
                        }
                    }
            } else {
                Text(tag)
                    .font(.system(size: 12))
            }
            if tag != "Clipboard History" {
                Button(action: {
                    model.removeTag(tag, from: item)
                    print("Removed tag '\(tag)' from item ID: \(item.id)")
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8))
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(Color.blue.opacity(0.2))
        .cornerRadius(4)
        .onTapGesture(count: 2) {
            isEditing = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.isTextFieldFocused = true
            }
        }
        .contextMenu {
            Button("Delete") {
                model.removeTag(tag, from: item)
                print("Context menu: Deleted tag '\(tag)' from item ID: \(item.id)")
                NotificationCenter.default.post(name: NSNotification.Name("RestoreFocus"), object: nil)
            }
            Button("Rename") {
                isEditing = true
                print("Context menu: Renaming tag '\(tag)' for item ID: \(item.id)")
            }
        }
    }

    private func commitEdit() {
        isEditing = false
        if editedTag != tag && !editedTag.isEmpty {
            model.renameTag(oldTag: tag, newTag: editedTag)
            print("Renamed tag from '\(tag)' to '\(editedTag)' for item ID: \(item.id)")
        }
    }
}


extension Date {
    func timeAgoString() -> String {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.year, .month, .weekOfYear, .day, .hour, .minute], from: self, to: now)

        if let years = components.year, years > 0 {
            return years == 1 ? "1 year ago" : "\(years) years ago"
        } else if let months = components.month, months > 0 {
            return months == 1 ? "1 month ago" : "\(months) months ago"
        } else if let weeks = components.weekOfYear, weeks > 0 {
            return weeks == 1 ? "1 week ago" : "\(weeks) weeks ago"
        } else if let days = components.day, days > 0 {
            return days == 1 ? "Yesterday" : "\(days) days ago"
        } else if let hours = components.hour, hours > 0 {
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        } else if let minutes = components.minute, minutes > 0 {
            return minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago"
        } else {
            return "Just now"
        }
    }
}


// Update the timeAgoString function in the ClipboardItemView
private func timeAgoString(from date: Date) -> String {
return date.timeAgoString()
}


struct CategoryDropDelegate: DropDelegate {
let category: String
@Binding var categories: [String]
@Binding var isDragging: Bool

func performDrop(info: DropInfo) -> Bool {
self.isDragging = false
return true
}

func dropEntered(info: DropInfo) {
guard let sourceCategory = info.itemProviders(for: [UTType.text]).first else { return }
sourceCategory.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { (item, error) in
DispatchQueue.main.async {
if let string = item as? String, let sourceIndex = self.categories.firstIndex(of: string), let destinationIndex = self.categories.firstIndex(of: self.category) {
if sourceIndex != destinationIndex {
withAnimation {
self.categories.move(fromOffsets: IndexSet(integer: sourceIndex), toOffset: destinationIndex > sourceIndex ? destinationIndex + 1 : destinationIndex)
}
}
}
}
}
}
}

import AppKit
// AppStateManager to track previous app
class AppStateManager: ObservableObject {
    static let shared = AppStateManager()
    @Published var previousApp: NSRunningApplication?

    private init() {
        startMonitoring()
    }

    private func startMonitoring() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    @objc private func appDidActivate(_ notification: Notification) {
        if let newApp = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
            if newApp.bundleIdentifier != Bundle.main.bundleIdentifier {
                previousApp = newApp
            }
        }
    }
}

extension ClipboardItem {
func copyToClipboard() {
let pasteboard = NSPasteboard.general
pasteboard.clearContents()
if type == "Text" {
pasteboard.setString(content, forType: .string)
} else if type == "Image", let imageData = imageData {
pasteboard.setData(imageData, forType: .png)
}
}
}
//
//struct LargeTextView: NSViewRepresentable {
//    let text: String
//
//    func makeCoordinator() -> Coordinator {
//        Coordinator()
//    }
//
//    func makeNSView(context: Context) -> NSScrollView {
//        let textView = NSTextView()
//        textView.isEditable = false
//        textView.isSelectable = true
//        textView.isRichText = false
//        textView.font = NSFont.systemFont(ofSize: 14)
//        textView.string = text
//
//        let scrollView = NSScrollView()
//        scrollView.documentView = textView
//        scrollView.hasVerticalScroller = true
//        scrollView.hasHorizontalScroller = false
//        scrollView.autohidesScrollers = true
//
//        // Assign the textView to the coordinator
//        context.coordinator.textView = textView
//        context.coordinator.setupObserver()
//
//        return scrollView
//    }
//
//    func updateNSView(_ nsView: NSScrollView, context: Context) {
//        if let textView = nsView.documentView as? NSTextView {
//            textView.string = text
//        }
//    }
//
//    class Coordinator {
//        var textView: NSTextView?
//        var observer: NSObjectProtocol?
//
//        func setupObserver() {
//            observer = NotificationCenter.default.addObserver(
//                forName: NSNotification.Name("PopoverDidShow"),
//                object: nil,
//                queue: .main
//            ) { [weak self] _ in
//                if let textView = self?.textView, let window = textView.window {
//                    window.makeFirstResponder(textView)
//                }
//            }
//        }
//
//        deinit {
//            if let observer = observer {
//                NotificationCenter.default.removeObserver(observer)
//            }
//        }
//    }
//}

import SwiftUI
import AppKit

struct LargeTextViewWithSearch: NSViewRepresentable {
    let text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: text)
    }

    func makeNSView(context: Context) -> NSView {
        let containerView = NSView()

        // 搜索字段
        let searchField = NSSearchField()
        searchField.placeholderString = "Search"
        searchField.delegate = context.coordinator

        // 上一个和下一个按钮
        let previousButton = NSButton(title: "Previous", target: context.coordinator, action: #selector(context.coordinator.goToPreviousMatch))
        let nextButton = NSButton(title: "Next", target: context.coordinator, action: #selector(context.coordinator.goToNextMatch))

        // 按钮的堆栈视图
        let buttonStack = NSStackView(views: [previousButton, nextButton])
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 5

        // 文本视图
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.string = text

        // 保存原始文本的属性字符串
        context.coordinator.originalAttributedString = textView.attributedString()

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        // 搜索区域的堆栈视图
        let searchStack = NSStackView(views: [searchField, buttonStack])
        searchStack.orientation = .horizontal
        searchStack.spacing = 5

        // 主堆栈视图
        let mainStack = NSStackView(views: [searchStack, scrollView])
        mainStack.orientation = .vertical
        mainStack.spacing = 5

        // 添加约束
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(mainStack)
        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            mainStack.topAnchor.constraint(equalTo: containerView.topAnchor),
            mainStack.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])

        // 将 textView 和其他控件分配给协调器
        context.coordinator.textView = textView
        context.coordinator.searchField = searchField
        context.coordinator.previousButton = previousButton
        context.coordinator.nextButton = nextButton

        return containerView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // 如果需要，可以在这里更新 NSView
    }

    class Coordinator: NSObject, NSSearchFieldDelegate {
        var textView: NSTextView?
        var searchField: NSSearchField?
        var previousButton: NSButton?
        var nextButton: NSButton?
        var originalAttributedString: NSAttributedString?

        var searchResults: [NSRange] = []
        var currentMatchIndex: Int = -1

        let text: String

        init(text: String) {
            self.text = text
        }

        func controlTextDidChange(_ obj: Notification) {
            performSearch()
        }

        func performSearch() {
            guard let textView = textView, let searchField = searchField, let originalAttributedString = originalAttributedString else { return }
            let searchString = searchField.stringValue

            // 恢复原始的属性字符串，以保留字体和颜色
            textView.textStorage?.setAttributedString(originalAttributedString)

            // 清空之前的搜索结果
            searchResults.removeAll()
            currentMatchIndex = -1

            // 如果搜索字符串为空，禁用按钮
            if searchString.isEmpty {
                previousButton?.isEnabled = false
                nextButton?.isEnabled = false
                return
            }

            // 将搜索字符串拆分为多个搜索词
            let searchTerms = searchString.components(separatedBy: " ").filter { !$0.isEmpty }

            let attributedString = textView.textStorage!

            // 对每个搜索词进行查找并高亮
            for term in searchTerms {
                var searchRange = NSRange(location: 0, length: attributedString.length)
                while searchRange.location < attributedString.length {
                    let foundRange = (attributedString.string as NSString).range(of: term, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange)
                    if foundRange.location != NSNotFound {
                        // 保存匹配结果
                        searchResults.append(foundRange)
                        // 应用高亮
                        attributedString.addAttribute(NSAttributedString.Key.backgroundColor, value: NSColor.yellow, range: foundRange)
                        // 更新搜索范围
                        let newLocation = foundRange.location + foundRange.length
                        searchRange = NSRange(location: newLocation, length: attributedString.length - newLocation)
                    } else {
                        // 没有更多匹配
                        break
                    }
                }
            }

            // 启用或禁用导航按钮
            let hasMatches = !searchResults.isEmpty
            previousButton?.isEnabled = hasMatches
            nextButton?.isEnabled = hasMatches

            if hasMatches {
                currentMatchIndex = 0
                highlightCurrentMatch()
            }
        }

        func highlightCurrentMatch() {
            guard let textView = textView else { return }
            if currentMatchIndex >= 0 && currentMatchIndex < searchResults.count {
                let range = searchResults[currentMatchIndex]
                textView.scrollRangeToVisible(range)
                textView.showFindIndicator(for: range)
            }
        }

        @objc func goToPreviousMatch() {
            if currentMatchIndex > 0 {
                currentMatchIndex -= 1
                highlightCurrentMatch()
            }
        }

        @objc func goToNextMatch() {
            if currentMatchIndex < searchResults.count - 1 {
                currentMatchIndex += 1
                highlightCurrentMatch()
            }
        }
    }
}
