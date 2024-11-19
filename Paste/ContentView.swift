// ContentView.swift

import SwiftUI
import Combine
import HotKey

struct ContentView: View {
    @StateObject private var model = ClipboardHistoryModel()
    @State private var showingTagDialog = false
    @State private var currentItem: ClipboardItem?
    @State private var newTag = ""
    @State private var selectedItems: Set<ClipboardItem> = [] // Changed from selectedItem

    @FocusState private var isSearchFieldFocused: Bool

    private let hotKey = HotKey(key: .space, modifiers: [.control, .option, .command])
    @State private var keyDownMonitor: Any?
    @State private var keyUpMonitor: Any?

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                searchBar
                ClipboardView(
                    model: model,
                    selectedCategory: $model.selectedCategory,
                    showingTagDialog: $showingTagDialog,
                    currentItem: $currentItem,
                    newTag: $newTag,
                    selectedItems: $selectedItems // Pass selectedItems
                )
                .frame(height: min(geometry.size.height * 0.8, 300))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ItemSelected"))) { _ in
            isSearchFieldFocused = false
        }
        .onAppear {
            setupHotKey()
            // Set initial focus to the search field
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.isSearchFieldFocused = true
            }
            // Add key event monitors
            keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if self.handleKeyDown(event) {
                    return nil // Consume the event
                } else {
                    return event // Pass the event along
                }
            }
            keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { event in
                if self.handleKeyUp(event) {
                    return nil // Consume the event
                } else {
                    return event // Pass the event along
                }
            }
        }
        .onDisappear {
            // Remove the event monitors to prevent accumulation
            if let keyDownMonitor = keyDownMonitor {
                NSEvent.removeMonitor(keyDownMonitor)
                self.keyDownMonitor = nil
            }
            if let keyUpMonitor = keyUpMonitor {
                NSEvent.removeMonitor(keyUpMonitor)
                self.keyUpMonitor = nil
            }
        }
        .sheet(isPresented: $showingTagDialog, onDismiss: {
            if selectedItems.isEmpty {
                DispatchQueue.main.async {
                    self.isSearchFieldFocused = true
                    print("Search bar focus set to true after TagDialog dismiss")
                }
            }
        }) {
            TagDialog(showingTagDialog: $showingTagDialog, currentItem: $currentItem, newTag: $newTag, model: model)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("UnfocusSearchBar"))) { _ in
            isSearchFieldFocused = false
            // Cancel first responder
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
        .environmentObject(model)
        // Add this to the body of ContentView, after other modifiers
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView()
        }
    }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        // Do not handle if a dialog is presented or a TextField is active
        if isSearchFieldFocused || showingTagDialog || isTextFieldActive() {
            return false // Let the focused view handle the event
        }
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "c" {
            // Handle Command+C
            if !selectedItems.isEmpty {
                copySelectedItemsToClipboard()
            }
            return true
        }
        switch event.keyCode {
        case 49: // Spacebar
            NotificationCenter.default.post(name: Notification.Name("SpacebarPressed"), object: nil)
            return true // Event was handled

        case 123: // Left Arrow
            moveSelectionLeft()
            return true // Event was handled

        case 124: // Right Arrow
            moveSelectionRight()
            return true // Event was handled

        default:
            return false // Event was not handled
        }
    }

    func handleKeyUp(_ event: NSEvent) -> Bool {
        // Do not handle spacebar if a dialog is presented
        if isSearchFieldFocused || showingTagDialog {
            return false // Let the focused view handle the event
        }
        switch event.keyCode {
        case 49: // Spacebar
            NotificationCenter.default.post(name: Notification.Name("SpacebarReleased"), object: nil)
            return true // Event was handled
        default:
            return false // Event was not handled
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

    func moveSelectionLeft() {
        NotificationCenter.default.post(name: Notification.Name("DismissPopover"), object: nil)
        guard !model.filteredItems.isEmpty else { return }

        if let firstSelectedItem = selectedItems.first,
           let currentIndex = model.filteredItems.firstIndex(of: firstSelectedItem) {
            if currentIndex > 0 {
                // Move to previous item
                selectedItems = [model.filteredItems[currentIndex - 1]]
            } else {
                // Already at the first item
                print("Already at the first item, cannot move left")
                return
            }
        } else {
            // If no item is selected, select the first one
            selectedItems = [model.filteredItems.first!]
        }
        NSApp.sendAction(#selector(NSResponder.becomeFirstResponder), to: nil, from: nil)
    }

    func moveSelectionRight() {
        NotificationCenter.default.post(name: Notification.Name("DismissPopover"), object: nil)
        guard !model.filteredItems.isEmpty else { return }

        if let firstSelectedItem = selectedItems.first,
           let currentIndex = model.filteredItems.firstIndex(of: firstSelectedItem) {
            if currentIndex < model.filteredItems.count - 1 {
                // Move to next item
                selectedItems = [model.filteredItems[currentIndex + 1]]
            } else {
                // Already at the last item
                print("Already at the last item, cannot move right")
                return
            }
        } else {
            // If no item is selected, select the first one
            selectedItems = [model.filteredItems.first!]
        }
        NSApp.sendAction(#selector(NSResponder.becomeFirstResponder), to: nil, from: nil)
    }

    func isTextFieldActive() -> Bool {
        if let firstResponder = NSApp.keyWindow?.firstResponder {
            return firstResponder is NSTextField || firstResponder is NSTextView
        }
        return false
    }

    private func setupHotKey() {
        hotKey.keyDownHandler = {
            withAnimation(.spring()) {
                // Toggle functionality if needed
            }
        }
    }

    private var searchBar: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("Search", text: $model.searchText)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    .focused($isSearchFieldFocused)
                    .onSubmit {
                        model.applyRegularSearch()
                    }

                if !model.searchText.isEmpty {
                    Button(action: {
                        model.searchText = ""
                        model.applyRegularSearch()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }

                if !model.isSearchingAllData && model.selectedCategory.lowercased() != "ai" {
                    Button(action: { model.isSearchingAllData = true }) {
                        Text("Search All")
                    }
                }

                if model.isSearching {
                                    ProgressView()
                                        .scaleEffect(0.5)
                                        .frame(width: 20, height: 20)
                                }
                                
                                // Settings button
                                Button(action: showSettings) {
                                    Image(systemName: "gear")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .padding(.leading, 4)
                            }
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .padding(.horizontal)
    }
    
    // Add these properties to ContentView
    @State private var isSettingsPresented = false

    // Add this method to ContentView
    private func showSettings() {
        isSettingsPresented = true
    }


}


struct TagDialog: View {
@Binding var showingTagDialog: Bool
@Binding var currentItem: ClipboardItem?
@Binding var newTag: String
@ObservedObject var model: ClipboardHistoryModel

// Focus state for the TextField
@FocusState private var isTextFieldFocused: Bool

var body: some View {
VStack(spacing: 16) {
Text("添加标签")
.font(.headline)
TextField("输入新标签", text: $newTag)
.onChange(of: newTag) { newValue in
if newValue.count > 20 {
newTag = String(newValue.prefix(20))
}
}
.textFieldStyle(RoundedBorderTextFieldStyle())
.padding(.horizontal)
.focused($isTextFieldFocused)
.onSubmit {
addTag()
}
HStack {
Spacer()
Button("取消") {
showingTagDialog = false
}
Button("添加") {
addTag()
}
.keyboardShortcut(.defaultAction) // Allows pressing Enter to activate this button
.disabled(newTag.isEmpty)
}
.padding(.horizontal)
}
.padding()
.frame(width: 300)
.background(Color(NSColor.windowBackgroundColor))
.cornerRadius(12)
.shadow(radius: 8)
.onAppear {
// Focus the TextField when the dialog appears
DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
self.isTextFieldFocused = true
}
}
}

private func addTag() {
if let item = currentItem, !newTag.isEmpty {
model.addTag(newTag, to: item)
newTag = ""
showingTagDialog = false
}
}
}
struct CategoryDialog: View {
@Binding var showingCategoryDialog: Bool
@Binding var newCategory: String
@ObservedObject var model: ClipboardHistoryModel

// Added FocusState for the new category TextField
@FocusState private var isTextFieldFocused: Bool

var body: some View {
VStack(spacing: 16) {
Text("Manage Categories")
.font(.headline)
HStack {
TextField("New category", text: $newCategory)
.textFieldStyle(RoundedBorderTextFieldStyle())
.focused($isTextFieldFocused) // Bind to FocusState
Button("Add") {
if !newCategory.isEmpty {
model.addCategory(newCategory)
newCategory = ""
isTextFieldFocused = true
}
if model.customCategories.count >= 6 {
Text("Maximum of 6 custom tags reached.")
.font(.caption)
.foregroundColor(.red)
}
}
.disabled(newCategory.isEmpty || model.customCategories.count >= 6)
}
.padding(.horizontal)
List {
ForEach(model.categories, id: \.self) { category in
HStack {
Text(category)
Spacer()
if category != "剪贴板历史记录" {
Button(action: {
model.removeCategory(category)
}) {
Image(systemName: "minus.circle")
.foregroundColor(.red)
}
}
}
}
}
.listStyle(PlainListStyle())
Button("Close") {
showingCategoryDialog = false
}
.padding(.top)
}
.padding()
.frame(width: 300, height: 400)
.background(Color(NSColor.windowBackgroundColor))
.cornerRadius(12)
.shadow(radius: 8)
.onAppear {
// Focus the TextField when the dialog appears
DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
self.isTextFieldFocused = true
}
}
}
}

struct RenameTagDialog: View {
@Binding var showingRenameDialog: Bool
@State private var newTag: String = ""
let currentTag: String
let item: ClipboardItem
@EnvironmentObject private var model: ClipboardHistoryModel

// Added FocusState for the TextField
@FocusState private var isTextFieldFocused: Bool

var body: some View {
VStack(spacing: 16) {
Text("Rename Tag")
.font(.headline)
TextField("New Tag", text: $newTag)
.textFieldStyle(RoundedBorderTextFieldStyle())
.padding(.horizontal)
.focused($isTextFieldFocused) // Bind to FocusState
.onSubmit {
renameTag()
}
HStack {
Button("Cancel") {
showingRenameDialog = false
}
Spacer()
Button("Rename") {
renameTag()
}
.disabled(newTag.isEmpty)
}
.padding(.horizontal)
}
.padding()
.frame(width: 300, height: 200)
.background(Color(NSColor.windowBackgroundColor))
.cornerRadius(12)
.shadow(radius: 8)
.onAppear {
// Focus the TextField when the dialog appears
DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
self.isTextFieldFocused = true
}
}
}

private func renameTag() {
if !newTag.isEmpty {
model.renameTag(oldTag: currentTag, newTag: newTag)
showingRenameDialog = false
}
}
}

struct APIKeyDialog: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var apiKey = ""
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        VStack(spacing: 16) {
            Text("OpenAI API Key")
                .font(.headline)
            
            TextField("Enter your OpenAI API key", text: $apiKey)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 300)
            
            if showError {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
            }
            
            HStack {
                Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
                
                Button("Save") {
                    if KeychainManager.shared.saveAPIKey(apiKey) {
                        presentationMode.wrappedValue.dismiss()
                    } else {
                        showError = true
                        errorMessage = "Failed to save API key"
                    }
                }
                .disabled(apiKey.isEmpty)
            }
        }
        .padding()
        .frame(width: 350, height: 200)
    }
}