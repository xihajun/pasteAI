import Foundation
import SQLite

class DatabaseManager {
    static let shared = DatabaseManager()
    private var db: Connection?

    // Tables
    private let clipboardItems = Table("clipboard_items")
    private let id = Expression<Int64>("id")
    private let type = Expression<String>("type")
    private let content = Expression<Data?>("content")
    private let timestamp = Expression<Date>("timestamp")
    private let source = Expression<String>("source")

    private let tags = Table("tags")
    private let tagId = Expression<Int64>("id")
    private let tagName = Expression<String>("name")

    private let itemTags = Table("item_tags")
    private let itemId = Expression<Int64>("item_id")
    private let tagIdFK = Expression<Int64>("tag_id")

    private let textContent = Expression<String?>("text_content")
    private let imageData = Expression<Data?>("image_data")

    private let maxItems = 10000000 // Maximum number of clipboard items to store

    private init() {
        do {
            let path = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true).first!
            let dbPath = "\(path)/ClipboardHistory_new.sqlite3"
            print("Database path: \(dbPath)")
            db = try Connection(dbPath)

            try db?.run(clipboardItems.create(ifNotExists: true) { t in
                t.column(id, primaryKey: .autoincrement)
                t.column(type)
                t.column(textContent)
                t.column(imageData)
                t.column(timestamp)
                t.column(source)
            })

            try db?.run(tags.create(ifNotExists: true) { t in
                t.column(tagId, primaryKey: .autoincrement)
                t.column(tagName, unique: true)
            })

            try db?.run(itemTags.create(ifNotExists: true) { t in
                t.column(itemId)
                t.column(tagIdFK)
                t.foreignKey(itemId, references: clipboardItems, id, delete: .cascade)
                t.foreignKey(tagIdFK, references: tags, tagId, delete: .cascade)
                t.primaryKey(itemId, tagIdFK)
            })

            print("Successfully initialized database with all required tables")
        } catch {
            print("Database initialization failed: \(error)")
        }
    }

    // MARK: - Core Database Operations
    @discardableResult
    func addClipboardItem(_ item: ClipboardItem) -> Int64 {
        guard let db = db else { return 0 }
        do {
            let insert = clipboardItems.insert(
                type <- item.type,
                textContent <- item.type == "Text" ? item.content : nil,
                imageData <- item.type == "Image" ? item.imageData : nil,
                timestamp <- item.timestamp,
                source <- item.source
            )
            let itemId = try db.run(insert)

            for tag in item.tags {
                try addTag(tag)
                if let tagId = getTagId(tag) {
                    try db.run(itemTags.insert(self.itemId <- itemId, tagIdFK <- tagId))
                }
            }
            enforceItemLimit()
            return itemId
        } catch {
            print("Failed to add clipboard item: \(error)")
            return 0
        }
    }

    private func enforceItemLimit() {
        guard let db = db else { return }
        do {
            let count = try db.scalar(clipboardItems.count)
            if count > maxItems {
                let excess = count - maxItems
                let oldestItems = clipboardItems.order(timestamp.asc).limit(excess)
                for item in try db.prepare(oldestItems) {
                    try db.run(itemTags.filter(self.itemId == item[id]).delete())
                    try db.run(clipboardItems.filter(id == item[id]).delete())
                }
            }
        } catch {
            print("Failed to enforce item limit: \(error)")
        }
    }

    func getClipboardItems(limit: Int = 1000, offset: Int = 0) -> [ClipboardItem] {
        guard let db = db else { return [] }
        var items: [ClipboardItem] = []
        do {
            for row in try db.prepare(clipboardItems.order(timestamp.desc).limit(limit, offset: offset)) {
                let itemId = row[id]
                let tags = try getTags(for: itemId)
                let item = ClipboardItem(
                    id: row[id],
                    type: row[type],
                    content: row[textContent] ?? "",
                    imageData: row[imageData],
                    timestamp: row[timestamp],
                    source: row[source],
                    tags: Set(tags)
                )
                items.append(item)
            }
        } catch {
            print("Failed to fetch clipboard items: \(error)")
        }
        return items
    }

    // MARK: - Tag Operations
    func addTag(_ tag: String) throws {
        try db?.run(tags.insert(or: .ignore, tagName <- tag))
    }

    private func getTagId(_ tag: String) -> Int64? {
        guard let db = db else { return nil }
        do {
            return try db.pluck(tags.filter(tagName == tag))?[tagId]
        } catch {
            print("Failed to get tag ID: \(error)")
            return nil
        }
    }

    private func getTags(for itemId: Int64) throws -> [String] {
        guard let db = db else { return [] }
        let query = tags
            .join(itemTags, on: tags[tagId] == itemTags[tagIdFK])
            .filter(itemTags[self.itemId] == itemId)
        return try db.prepare(query).map { $0[tagName] }
    }

    func addTagToItem(_ tag: String, itemId: Int64) {
        do {
            try addTag(tag)
            if let tagId = getTagId(tag) {
                try db?.run(itemTags.insert(or: .ignore, self.itemId <- itemId, tagIdFK <- tagId))
            }
        } catch {
            print("Failed to add tag to item: \(error)")
        }
    }

    func removeTagFromItem(_ tag: String, itemId: Int64) {
        guard let db = db, let tagId = getTagId(tag) else { return }
        do {
            try db.run(itemTags.filter(self.itemId == itemId && tagIdFK == tagId).delete())
        } catch {
            print("Failed to remove tag from item: \(error)")
        }
    }

    func getAllTags() -> [String] {
        guard let db = db else { return [] }
        do {
            return try db.prepare(tags.select(tagName)).map { $0[tagName] }
        } catch {
            print("Failed to fetch all tags: \(error)")
            return []
        }
    }

    func removeTag(_ tag: String) {
        guard let db = db, let tagId = getTagId(tag) else { return }
        do {
            try db.transaction {
                try db.run(itemTags.filter(tagIdFK == tagId).delete())
                try db.run(tags.filter(self.tagId == tagId).delete())
            }
        } catch {
            print("Failed to remove tag: \(error)")
        }
    }

    func deleteClipboardItem(_ itemId: Int64) {
        guard let db = db else { return }
        do {
            try db.transaction {
                try db.run(itemTags.filter(self.itemId == itemId).delete())
                try db.run(clipboardItems.filter(id == itemId).delete())
            }
        } catch {
            print("Failed to delete clipboard item: \(error)")
        }
    }

    func renameTag(oldTag: String, newTag: String) {
        guard let db = db else { return }
        do {
            try db.transaction {
                if let tagId = getTagId(oldTag) {
                    let existingTag = tags.filter(self.tagName == newTag)
                    if try db.scalar(existingTag.count) > 0 {
                        throw NSError(domain: "", code: 1, userInfo: [NSLocalizedDescriptionKey: "Tag '\(newTag)' already exists."])
                    }
                    try db.run(tags.filter(self.tagName == oldTag).update(tagName <- newTag))
                    print("Database: Renamed tag '\(oldTag)' to '\(newTag)'.")
                } else {
                    throw NSError(domain: "", code: 2, userInfo: [NSLocalizedDescriptionKey: "Tag '\(oldTag)' not found."])
                }
            }
        } catch {
            print("Failed to rename tag in database: \(error.localizedDescription)")
        }
    }

    func searchClipboardItems(searchText: String, category: String) -> [ClipboardItem] {
        guard let db = db else { return [] }
        var items: [ClipboardItem] = []
        do {
            var query = clipboardItems

            if category != "Clipboard History" {
                if let tagId = getTagId(category) {
                    query = query
                        .join(itemTags, on: itemTags[itemId] == clipboardItems[id])
                        .filter(itemTags[tagIdFK] == tagId)
                }
            }

            if !searchText.isEmpty {
                let likePattern = "%\(searchText)%"
                query = query.filter(textContent.like(likePattern))
            }

            query = query.order(timestamp.desc)
            for row in try db.prepare(query) {
                let itemId = row[id]
                let tags = try getTags(for: itemId)
                let item = ClipboardItem(
                    id: row[id],
                    type: row[type],
                    content: row[textContent] ?? "",
                    imageData: row[imageData],
                    timestamp: row[timestamp],
                    source: row[source],
                    tags: Set(tags)
                )
                items.append(item)
            }
        } catch {
            print("Failed to search clipboard items: \(error)")
        }
        return items
    }

    func getClipboardItem(id itemId: Int64) -> ClipboardItem? {
        guard let db = db else { return nil }
        do {
            if let row = try db.pluck(clipboardItems.filter(self.id == itemId)) {
                let tags = try getTags(for: row[self.id])
                return ClipboardItem(
                    id: row[self.id],
                    type: row[type],
                    content: row[textContent] ?? "",
                    imageData: row[imageData],
                    timestamp: row[timestamp],
                    source: row[source],
                    tags: Set(tags)
                )
            }
        } catch {
            print("Failed to get clipboard item: \(error)")
        }
        return nil
    }
}

// MARK: - Embedding Tables Extension
extension DatabaseManager {
    struct EmbeddingTables {
        static let local = Table("local_embeddings")
        static let google = Table("google_embeddings")
        static let openai = Table("openai_embeddings")
    }
    
    private var currentEmbeddingTable: Table {
        let settings = EmbeddingSettingsManager.shared.currentSettings
        switch settings.provider {
        case .local:
            return EmbeddingTables.local
        case .google:
            return EmbeddingTables.google
        case .openAI:
            return EmbeddingTables.openai
        }
    }
}

// MARK: - Embedding Setup Extension
extension DatabaseManager {
    func setupEmbeddingTables() {
        print("Setting up embedding tables...")
        do {
            // Create local embeddings table
            try db?.run(Table("local_embeddings").create(ifNotExists: true) { t in
                t.column(Expression<Int64>("id"), primaryKey: true)
                t.column(Expression<Data>("vector"))
                t.foreignKey(Expression<Int64>("id"), references: clipboardItems, Expression<Int64>("id"), delete: .cascade)
            })

            // Create Google embeddings table
            try db?.run(Table("google_embeddings").create(ifNotExists: true) { t in
                t.column(Expression<Int64>("id"), primaryKey: true)
                t.column(Expression<Data>("vector"))
                t.foreignKey(Expression<Int64>("id"), references: clipboardItems, Expression<Int64>("id"), delete: .cascade)
            })

            // Create OpenAI embeddings table
            try db?.run(Table("openai_embeddings").create(ifNotExists: true) { t in
                t.column(Expression<Int64>("id"), primaryKey: true)
                t.column(Expression<Data>("vector"))
                t.foreignKey(Expression<Int64>("id"), references: clipboardItems, Expression<Int64>("id"), delete: .cascade)
            })
            
            print("✅ Successfully created embedding tables")
        } catch {
            print("❌ Failed to create embedding tables: \(error)")
        }
    }

    func ensureEmbeddingTablesExist() {
        do {
            let settings = EmbeddingSettingsManager.shared.currentSettings
            let tableName = getTableName(for: settings.provider)
            
            // Check if the current embedding table exists
            let tableExists = try db?.scalar("SELECT count(*) FROM sqlite_master WHERE type = 'table' AND name = ?", tableName) as? Int64 ?? 0 > 0
            
            if !tableExists {
                print("📦 Embedding tables not found. Creating tables...")
                setupEmbeddingTables()
            } else {
                print("✓ Embedding tables already exist")
            }
        } catch {
            print("❌ Error checking embedding tables: \(error)")
            setupEmbeddingTables()
        }
    }
}

// MARK: - Embedding Operations Extension
extension DatabaseManager {
    func saveEmbedding(vector embedding: [Float], forItem itemId: Int64) throws {
        guard let db = db else { return }
        
        // Ensure tables exist before saving
        ensureEmbeddingTablesExist()
        
        let settings = EmbeddingSettingsManager.shared.currentSettings
        let tableName = getTableName(for: settings.provider)
        print("💾 Attempting to save embedding to table: \(tableName) for item \(itemId)")
        
        let data = Data(bytes: embedding, count: embedding.count * MemoryLayout<Float>.stride)
        do {
            try db.run(currentEmbeddingTable.insert(or: .replace,
                Expression<Int64>("id") <- itemId,
                Expression<Data>("vector") <- data
            ))
            print("✅ Successfully saved embedding for item \(itemId) to \(tableName)")
        } catch {
            print("❌ Failed to save embedding to \(tableName): \(error)")
            throw error
        }
    }

    private func getTableName(for provider: EmbeddingProvider) -> String {
        switch provider {
        case .local:
            return "local_embeddings"
        case .google:
            return "google_embeddings"
        case .openAI:
            return "openai_embeddings"
        }
    }

    func getEmbedding(forItem itemId: Int64) throws -> [Float]? {
            guard let db = db else { return nil }
            
            // Ensure tables exist before querying
            ensureEmbeddingTablesExist()
            
            guard let row = try db.pluck(currentEmbeddingTable.filter(Expression<Int64>("id") == itemId)) else {
                return nil
            }
            
            let data = row[Expression<Data>("vector")]
            let count = data.count / MemoryLayout<Float>.stride
            return data.withUnsafeBytes { pointer in
                Array(UnsafeBufferPointer(
                    start: pointer.baseAddress?.assumingMemoryBound(to: Float.self),
                    count: count
                ))
            }
        }
        
        func clearCurrentEmbeddings() {
            guard let db = db else { return }
            do {
                ensureEmbeddingTablesExist()
                try db.run(currentEmbeddingTable.delete())
                print("✅ Successfully cleared current embeddings table")
            } catch {
                print("❌ Failed to clear embeddings: \(error)")
            }
        }
    }

    // MARK: - Embedding Query Extension
    extension DatabaseManager {
        func getTextItemsWithoutEmbeddings() -> [ClipboardItem] {
            guard let db = db else { return [] }
            var items: [ClipboardItem] = []
            
            do {
                ensureEmbeddingTablesExist()
                
                let textItems = clipboardItems
                    .filter(type == "Text")
                    .filter(textContent != nil)
                
                for row in try db.prepare(textItems) {
                    let itemId = row[id]
                    // Check if embedding exists
                    let hasEmbedding = try db.scalar(currentEmbeddingTable.filter(Expression<Int64>("id") == itemId).count) > 0
                    
                    if !hasEmbedding {
                        let tags = try getTags(for: itemId)
                        let item = ClipboardItem(
                            id: itemId,
                            type: row[type],
                            content: row[textContent] ?? "",
                            imageData: row[imageData],
                            timestamp: row[timestamp],
                            source: row[source],
                            tags: Set(tags)
                        )
                        items.append(item)
                    }
                }
            } catch {
                print("❌ Failed to fetch text items without embeddings: \(error)")
            }
            
            return items
        }
        
        func performSemanticSearch(queryEmbedding: [Float], limit: Int = 30) throws -> [(itemId: Int64, similarity: Float)] {
            guard let db = db else { return [] }
            var results: [(Int64, Float)] = []
            
            ensureEmbeddingTablesExist()
            
            let rows = try db.prepare(currentEmbeddingTable)
            for row in rows {
                let itemId = row[Expression<Int64>("id")]
                let embeddingData = row[Expression<Data>("vector")]
                
                let count = embeddingData.count / MemoryLayout<Float>.stride
                let embedding = embeddingData.withUnsafeBytes { pointer in
                    Array(UnsafeBufferPointer(
                        start: pointer.baseAddress?.assumingMemoryBound(to: Float.self),
                        count: count
                    ))
                }
                
                let similarity = cosineSimilarity(queryEmbedding, embedding)
                results.append((itemId, similarity))
            }
            
            return results
                .sorted { $0.1 > $1.1 }
                .prefix(limit)
                .map { ($0.0, $0.1) }
        }
        
        private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
            guard a.count == b.count else { return 0 }
            
            let dotProduct = zip(a, b).map(*).reduce(0, +)
            let normA = sqrt(a.map { $0 * $0 }.reduce(0, +))
            let normB = sqrt(b.map { $0 * $0 }.reduce(0, +))
            
            return dotProduct / (normA * normB)
        }
    }
extension DatabaseManager {
    func getCategoryId(_ category: String) -> Int64? {
        guard let db = db else { return nil }
        do {
            if let row = try db.pluck(tags.filter(tagName == category)) {
                return row[tagId]
            }
            return nil
        } catch {
            print("Failed to get category ID for '\(category)': \(error)")
            return nil
        }
    }
    
//    // If you need a more descriptive name, you can also add an alias:
//    func getTagId(_ tag: String) -> Int64? {
//        return getCategoryId(tag)
//    }
}
