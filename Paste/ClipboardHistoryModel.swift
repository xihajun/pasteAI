// ClipboardHistoryModel.swift

import SwiftUI
import AppKit
import Combine
import Foundation

struct ClipboardItem: Identifiable, Equatable, Hashable {
    let id: Int64
    let type: String
    let content: String
    let imageData: Data?
    let timestamp: Date
    let source: String // Store the app's bundle identifier
    var tags: Set<String>
}

class ClipboardHistoryModel: ObservableObject {
    @Published var items: [ClipboardItem] = []
    @Published var categories: [String] = ["Clipboard History", "AI"]
    @Published var filteredItems: [ClipboardItem] = []

    @Published var searchText: String = ""
    @Published var selectedCategory: String = "Clipboard History"
    @Published var isSearchingAllData: Bool = false
    @Published var searchError: String? = nil

    private var lastClipboardText: String = ""
    private var lastClipboardImageData: Data? = nil
    private var clipboardTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    // Pagination properties
    private let itemsPerPage = 10
    private var currentOffset = 0
    public var isLoading = false
    public var hasMoreItems = true

    var customCategories: [String] {
        return categories.filter { $0 != "Clipboard History" && $0 != "AI" }
    }

    // Image Cache
    private let imageCache = NSCache<NSNumber, NSImage>()

    // New property to track semantic search state
    @Published var isPerformingSemanticSearch = false
    @Published var isSearching = false
    @Published var embeddingProvider: EmbeddingProvider {
        didSet {
            if oldValue != embeddingProvider {
                // Clear existing search results when switching providers
                if isPerformingSemanticSearch {
                    isPerformingSemanticSearch = false
                    applyRegularSearch()
                }
            }
        }
    }
    
    init() {
        self.embeddingProvider = EmbeddingSettingsManager.shared.currentSettings.provider
        
        // Continue with existing initialization
        loadCategories()
        loadInitialItems()
        startMonitoringClipboard()
        setupSearch()
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("EmbeddingSettingsChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.embeddingProvider = EmbeddingSettingsManager.shared.currentSettings.provider
        }
    }


    deinit {
        clipboardTimer?.invalidate()
    }

    func loadCategories() {
        categories = ["Clipboard History", "AI"] + DatabaseManager.shared.getAllTags()
    }

    internal func loadInitialItems() {
        currentOffset = 0
        hasMoreItems = true
        items = []
        loadMoreItems()
    }

    func loadMoreItems() {
        guard !isLoading && hasMoreItems && !isSearchingAllData && !isPerformingSemanticSearch else { return }
        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let newItems = DatabaseManager.shared.getClipboardItems(limit: self.itemsPerPage, offset: self.currentOffset)

            DispatchQueue.main.async {
                // Filter out duplicate items based on their IDs
                let existingIDs = Set(self.items.map { $0.id })
                let uniqueNewItems = newItems.filter { !existingIDs.contains($0.id) }

                self.items.append(contentsOf: uniqueNewItems)
                if !self.isSearchingAllData && !self.isPerformingSemanticSearch {
                    self.filteredItems = self.applyFiltersToItems(self.items)
                }
                self.currentOffset += self.itemsPerPage
                self.hasMoreItems = newItems.count == self.itemsPerPage
                self.isLoading = false
            }
        }
    }

    private func loadCategoriesAndItems() {
        loadCategories()
        loadInitialItems()
    }

    func startMonitoringClipboard() {
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkClipboardContent()
        }
    }

    func checkClipboardContent() {
        Task {
            // Read clipboard on the main thread
            let clipboardText = NSPasteboard.general.string(forType: .string)
            let imageData = NSPasteboard.general.data(forType: .png)

            // Check text
            if let text = clipboardText, text != lastClipboardText {
                await addNewItem(type: "Text", content: text)
                lastClipboardText = text
            }

            // Check image
            if let data = imageData, data != lastClipboardImageData {
                await addNewItem(type: "Image", imageData: data)
                lastClipboardImageData = data
            }
        }
    }

    
    private func addNewItem(type: String, content: String? = nil, imageData: Data? = nil) async {
        print("📎 Adding new clipboard item of type: \(type)")
        
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let appBundleIdentifier = frontmostApp?.bundleIdentifier ?? "Unknown"
        
        let newItem = ClipboardItem(
            id: 0,
            type: type,
            content: content ?? "",
            imageData: imageData,
            timestamp: Date(),
            source: appBundleIdentifier,
            tags: []
        )
        
        // Add the item to the database
        let itemId = DatabaseManager.shared.addClipboardItem(newItem)
        print("💾 Item saved to database with ID: \(itemId)")
        
        // Generate and store embedding for text items
        if type == "Text", let content = content {
            print("🤖 Starting embedding generation for text item...")
            do {
                let embedding = try await EmbeddingService.shared.generateEmbedding(for: content)
                print("📊 Generated embedding with \(embedding.count) dimensions")
                try DatabaseManager.shared.saveEmbedding(vector: embedding, forItem: itemId)
                print("✅ Embedding saved to database for item ID: \(itemId)")
            } catch {
                print("❌ Failed to generate or save embedding: \(error)")
            }
        }
        
        // Update UI on the main thread
        await MainActor.run {
            self.loadInitialItems()
        }
    }

    func performSemanticSearch() {
            guard !searchText.isEmpty else {
                print("🔍 Search text is empty, showing all items")
                self.filteredItems = self.items
                return
            }
            
            isSearching = true
            isPerformingSemanticSearch = true
            searchError = nil // Clear previous error
            print("🔍 Starting semantic search for: \(searchText)")
            
            Task {
                do {
                    let queryEmbedding = try await EmbeddingService.shared.generateEmbedding(for: searchText)
                    let searchResults = try DatabaseManager.shared.performSemanticSearch(queryEmbedding: queryEmbedding)
                    
                    let matchingItems = try searchResults.compactMap { result -> (ClipboardItem, Float)? in
                        if let item = DatabaseManager.shared.getClipboardItem(id: result.itemId) {
                            return (item, result.similarity)
                        }
                        return nil
                    }
                    
                    let threshold: Float = 0.7
                    let filteredItems = matchingItems
                        .filter { $0.1 >= threshold }
                        .map { $0.0 }
                    
                    await MainActor.run {
                        self.filteredItems = filteredItems
                        self.isSearching = false
                        print("📊 Showing \(filteredItems.count) items with similarity >= \(threshold)")
                    }
                } catch {
                    await MainActor.run {
                        self.isSearching = false
                        // Don't reset isPerformingSemanticSearch here
                        
                        // Set error message
                        if let embeddingError = error as? EmbeddingError {
                            self.searchError = embeddingError.localizedDescription
                        } else {
                            self.searchError = error.localizedDescription
                        }
                        
                        // Clear results but don't fall back to regular search
                        self.filteredItems = []
                        
                        print("❌ Semantic search failed: \(error)")
                    }
                }
            }
        }

        func applyRegularSearch() {
            isPerformingSemanticSearch = false
            searchError = nil // Clear any previous error
            applyFilters(searchText: searchText, selectedCategory: selectedCategory, isSearchingAllData: isSearchingAllData)
        }

    func addTag(_ tag: String, to item: ClipboardItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].tags.insert(tag)
            DatabaseManager.shared.addTagToItem(tag, itemId: item.id)
            loadCategories()
            applyFilters()
        }
    }

    func renameTag(oldTag: String, newTag: String) {
        let trimmedNewTag = newTag.trimmingCharacters(in: .whitespacesAndNewlines)

        // Prevent empty tag names
        guard !trimmedNewTag.isEmpty else {
            print("Rename failed: New tag name is empty.")
            return
        }

        // Prevent duplicate tag names
        guard !categories.contains(trimmedNewTag) else {
            print("Rename failed: Tag '\(trimmedNewTag)' already exists.")
            return
        }

        // Proceed with renaming
        for index in items.indices {
            if items[index].tags.contains(oldTag) {
                items[index].tags.remove(oldTag)
                items[index].tags.insert(trimmedNewTag)
            }
        }

        // Update categories
        if let oldTagIndex = categories.firstIndex(of: oldTag) {
            categories[oldTagIndex] = trimmedNewTag
        }

        // Update the database
        DatabaseManager.shared.renameTag(oldTag: oldTag, newTag: trimmedNewTag)

        // Reload categories to reflect changes from the database
        loadCategories()

        // Notify observers of the change
        objectWillChange.send()
        applyFilters()

        print("Successfully renamed tag '\(oldTag)' to '\(trimmedNewTag)'.")
    }

    func addCategory(_ category: String) {
        if !categories.contains(category) {
            do {
                try DatabaseManager.shared.addTag(category)
                loadCategories()
                applyFilters()
            } catch {
                print("Failed to add category: \(error)")
            }
        }
    }

    func removeCategory(_ category: String) {
        if category != "Clipboard History" && category != "AI" {
            DatabaseManager.shared.removeTag(category)
            loadCategories()
            applyFilters()
        }
    }

    func deleteEntireTag(_ tag: String) {
        // Remove the tag from items in memory
        for index in items.indices {
            if items[index].tags.contains(tag) {
                items[index].tags.remove(tag)
            }
        }

        // Remove the tag from the database
        DatabaseManager.shared.removeTag(tag)

        // Reload categories and apply filters
        loadCategories()
        applyFilters()
    }

    func removeTag(_ tag: String, from item: ClipboardItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].tags.remove(tag)
            DatabaseManager.shared.removeTagFromItem(tag, itemId: item.id)
            loadCategories()
            applyFilters()
            objectWillChange.send()
        }
    }

    func deleteClipboardItem(_ item: ClipboardItem) {
        DatabaseManager.shared.deleteClipboardItem(item.id)
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items.remove(at: index)
            applyFilters()
        }
    }

    private func setupSearch() {
        // Listen for changes in searchText
        $searchText
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] text in
                guard let self = self else { return }
                if self.selectedCategory.lowercased() == "ai" && !text.isEmpty {
                    self.performSemanticSearch()
                } else {
                    self.isPerformingSemanticSearch = false
                    self.applyRegularSearch()
                }
            }
            .store(in: &cancellables)

        // Listen for changes in selectedCategory and isSearchingAllData
        Publishers.CombineLatest(
            $selectedCategory.removeDuplicates(),
            $isSearchingAllData.removeDuplicates()
        )
        .sink { [weak self] category, isSearchingAllData in
            guard let self = self else { return }
            if category.lowercased() == "ai" && !self.searchText.isEmpty {
                self.performSemanticSearch()
            } else {
                self.isPerformingSemanticSearch = false
                self.applyFilters(selectedCategory: category, isSearchingAllData: isSearchingAllData)
            }
        }
        .store(in: &cancellables)
    }

    private func applyFilters(searchText: String? = nil, selectedCategory: String? = nil, isSearchingAllData: Bool? = nil) {
        let search = searchText ?? self.searchText
        let category = (selectedCategory ?? self.selectedCategory).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let searchAll = isSearchingAllData ?? self.isSearchingAllData

        if isPerformingSemanticSearch {
            // Do not apply regular filters when performing semantic search
            return
        }

        if searchAll {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                let matchingItems = DatabaseManager.shared.searchClipboardItems(searchText: search, category: category)

                // Remove duplicates while preserving order
                var seenIds = Set<Int64>()
                let uniqueItems = matchingItems.filter { item in
                    if seenIds.contains(item.id) {
                        return false
                    } else {
                        seenIds.insert(item.id)
                        return true
                    }
                }
                DispatchQueue.main.async {
                    withAnimation {
                        self.filteredItems = uniqueItems
                    }
                }
            }
        } else {
            // Existing code to filter self.items
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                let lowercasedSearch = search.lowercased()
                let filtered = self.items.filter { item in
                    let categoryMatch = category == "clipboard history" || item.tags.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == category }
                    let searchMatch = lowercasedSearch.isEmpty || self.itemMatchesSearch(item, searchText: lowercasedSearch)
                    return categoryMatch && searchMatch
                }
                print("Filtered \(filtered.count) items from loaded items.")
                DispatchQueue.main.async {
                    withAnimation {
                        self.filteredItems = filtered
                        print("Filtered items updated with loaded items.")
                    }
                }
            }
        }
    }

    private func applyFiltersToItems(_ items: [ClipboardItem]) -> [ClipboardItem] {
        let search = self.searchText.lowercased()
        let category = self.selectedCategory

        return items.filter { item in
            let categoryMatch = category == "Clipboard History" || item.tags.contains(category)
            let searchMatch = search.isEmpty || itemMatchesSearch(item, searchText: search)
            return categoryMatch && searchMatch
        }
    }

    private func itemMatchesSearch(_ item: ClipboardItem, searchText: String) -> Bool {
        let searchTerms = searchText.split(separator: " ")
        if item.type == "Text" {
            let itemContent = item.content.lowercased()
            return searchTerms.allSatisfy { term in
                itemContent.contains(term)
            }
        } else if item.type == "Image" {
            let tagString = item.tags.joined(separator: " ").lowercased()
            return searchTerms.allSatisfy { term in
                tagString.contains(term)
            }
        } else if item.type == "Link" {
            let itemContent = item.content.lowercased()
            let tagString = item.tags.joined(separator: " ").lowercased()
            return searchTerms.allSatisfy { term in
                itemContent.contains(term) || tagString.contains(term)
            }
        }
        return false
    }

    // Image Caching
    func getImage(for item: ClipboardItem) -> NSImage? {
        if let cachedImage = imageCache.object(forKey: NSNumber(value: item.id)) {
            return cachedImage
        }

        if let data = item.imageData,
           let nsImage = createNSImage(from: data) {
            imageCache.setObject(nsImage, forKey: NSNumber(value: item.id))
            return nsImage
        }
        return nil
    }

    private func createNSImage(from data: Data) -> NSImage? {
        if let cgImageSource = CGImageSourceCreateWithData(data as CFData, nil),
           let cgImage = CGImageSourceCreateImageAtIndex(cgImageSource, 0, nil) {
            return NSImage(cgImage: cgImage, size: NSZeroSize)
        }
        return nil
    }

    func getCategoryId(_ category: String) -> Int64? {
        return DatabaseManager.shared.getCategoryId(category)
    }
//
//    func performSemanticSearch() {
//        guard !searchText.isEmpty else {
//            print("🔍 Search text is empty, showing all items")
//            self.filteredItems = self.items
//            return
//        }
//        
//        isSearching = true
//        isPerformingSemanticSearch = true
//        print("🔍 Starting semantic search for: \(searchText)")
//        
//        Task {
//            do {
//                let queryEmbedding = try await EmbeddingService.shared.generateEmbedding(for: searchText)
//                let searchResults = try DatabaseManager.shared.performSemanticSearch(queryEmbedding: queryEmbedding)
//                
//                let matchingItems = try searchResults.compactMap { result -> (ClipboardItem, Float)? in
//                    if let item = DatabaseManager.shared.getClipboardItem(id: result.itemId) {
//                        return (item, result.similarity)
//                    }
//                    return nil
//                }
//                
//                let threshold: Float = 0.7
//                let filteredItems = matchingItems
//                    .filter { $0.1 >= threshold }
//                    .map { $0.0 }
//                
//                await MainActor.run {
//                    self.filteredItems = filteredItems
//                    self.isSearching = false
//                    print("📊 Showing \(filteredItems.count) items with similarity >= \(threshold)")
//                }
//            } catch {
//                await MainActor.run {
//                    self.isSearching = false
//                    self.isPerformingSemanticSearch = false
//                    print("❌ Semantic search failed: \(error)")
//                    print("↩️ Falling back to regular search")
//                    self.applyRegularSearch()
//                }
//            }
//        }
//    }

//    func applyRegularSearch() {
//        applyFilters(searchText: searchText, selectedCategory: selectedCategory, isSearchingAllData: isSearchingAllData)
//    }
}
