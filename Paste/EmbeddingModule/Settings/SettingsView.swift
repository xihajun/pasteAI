import SwiftUI

struct SettingsView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var settings: EmbeddingSettings
    @State private var isProcessingEmbeddings = false
    @State private var processedCount = 0
    @State private var totalCount = 0
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var processingTask: Task<Void, Error>?
    @State private var showConfirmClearDialog = false
    
    // Add validation states
    @State private var isTestingConnection = false
    @State private var connectionStatus: ConnectionStatus = .none
    
    enum ConnectionStatus {
        case none
        case testing
        case success
        case failure(String)
    }
    
    init() {
        _settings = State(initialValue: EmbeddingSettingsManager.shared.currentSettings)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Embedding Settings")
                .font(.title2)
                .padding(.top)
            
            // Provider Selection
            VStack(alignment: .leading, spacing: 8) {
                Text("Embedding Provider")
                    .font(.headline)
                Picker("Provider", selection: $settings.provider) {
                    ForEach(EmbeddingProvider.allCases, id: \.self) { provider in
                        Text(provider.rawValue).tag(provider)
                    }
                }
                .pickerStyle(RadioGroupPickerStyle())
            }
            
            // Provider-specific settings
            Group {
                switch settings.provider {
                case .local:
                    localSettingsView
                case .google:
                    googleSettingsView
                case .openAI:
                    openAISettingsView
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            
            // Test Connection Button
            HStack {
                Button(action: testConnection) {
                    if isTestingConnection {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Text("Test Connection")
                    }
                }
                .disabled(isTestingConnection)
                
                // Connection status indicator
                connectionStatusView
            }
            
            Divider()
            
            // Process Missing Embeddings Section
            VStack(spacing: 10) {
                if isProcessingEmbeddings {
                    ProgressView("Processing \(processedCount)/\(totalCount)")
                        .progressViewStyle(LinearProgressViewStyle())
                        .frame(width: 300)
                }
                
                HStack(spacing: 20) {
                    if isProcessingEmbeddings {
                        Button(action: stopProcessing) {
                            HStack {
                                Image(systemName: "stop.circle")
                                Text("Stop Processing")
                            }
                            .foregroundColor(.red)
                        }
                    } else {
                        Button(action: processHistoricalEmbeddings) {
                            HStack {
                                Image(systemName: "arrow.clockwise.circle")
                                Text("Process Missing Embeddings")
                            }
                        }
                    }
                    
                    // Clear Embeddings Button
                    Button(action: { showConfirmClearDialog = true }) {
                        HStack {
                            Image(systemName: "trash")
                            Text("Clear Current Embeddings")
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            
            Spacer()
            
            // Save/Cancel Buttons
            HStack {
                Button("Cancel") {
                    if isProcessingEmbeddings {
                        stopProcessing()
                    }
                    presentationMode.wrappedValue.dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Save") {
                    saveSettings()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.bottom)
        }
        .frame(width: 500, height: 600)
        .padding()
        .alert(isPresented: $showAlert) {
            Alert(
                title: Text("Processing Status"),
                message: Text(alertMessage),
                dismissButton: .default(Text("OK"))
            )
        }
        .confirmationDialog(
            "Clear Current Embeddings",
            isPresented: $showConfirmClearDialog,
            titleVisibility: .visible
        ) {
            Button("Clear Embeddings", role: .destructive) {
                clearCurrentEmbeddings()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all embeddings for the current provider. This action cannot be undone.")
        }
    }
    
    private var localSettingsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Local Server Settings")
                .font(.headline)
            TextField("Base URL", text: $settings.localBaseURL)
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
    }
    
    private var googleSettingsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Google AI Settings")
                .font(.headline)
            
            SecureField("API Key", text: $settings.googleAPIKey)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            TextField("Model", text: $settings.googleModel)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .disabled(true) // Since we're using a fixed model
        }
    }
    
    private var openAISettingsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OpenAI Settings")
                .font(.headline)
            
            SecureField("API Key", text: $settings.openAIAPIKey)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            TextField("Model", text: $settings.openAIModel)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .disabled(true) // Since we're using a fixed model
        }
    }
    
    private var connectionStatusView: some View {
        Group {
            switch connectionStatus {
            case .none:
                EmptyView()
            case .testing:
                ProgressView()
                    .scaleEffect(0.8)
            case .success:
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
            case .failure(let error):
                Label(error, systemImage: "xmark.circle.fill")
                    .foregroundColor(.red)
            }
        }
    }
    
    private func testConnection() {
        isTestingConnection = true
        connectionStatus = .testing
        
        Task {
            do {
                // Use a simple test text
                let testText = "Test connection"
                let _ = try await EmbeddingService.shared.generateEmbedding(for: testText)
                
                await MainActor.run {
                    connectionStatus = .success
                    isTestingConnection = false
                }
            } catch {
                await MainActor.run {
                    connectionStatus = .failure(error.localizedDescription)
                    isTestingConnection = false
                }
            }
        }
    }
    
    private func clearCurrentEmbeddings() {
        DatabaseManager.shared.clearCurrentEmbeddings()
        showAlert = true
        alertMessage = "All embeddings have been cleared for the current provider."
    }
    
    private func stopProcessing() {
        processingTask?.cancel()
        processingTask = nil
        isProcessingEmbeddings = false
        showAlert = true
        alertMessage = "Processing stopped. Processed \(processedCount) out of \(totalCount) items."
    }
    
    private func saveSettings() {
        // Save settings
        EmbeddingSettingsManager.shared.currentSettings = settings
        presentationMode.wrappedValue.dismiss()
    }
    
    private func processHistoricalEmbeddings() {
        isProcessingEmbeddings = true
        
        processingTask = Task {
            do {
                let items = DatabaseManager.shared.getTextItemsWithoutEmbeddings()
                await MainActor.run {
                    totalCount = items.count
                    processedCount = 0
                }
                
                for item in items {
                    try Task.checkCancellation()
                    
                    do {
                        let embedding = try await EmbeddingService.shared.generateEmbedding(for: item.content)
                        try DatabaseManager.shared.saveEmbedding(vector: embedding, forItem: item.id)
                        await MainActor.run {
                            processedCount += 1
                        }
                    } catch {
                        print("Error processing item \(item.id): \(error)")
                    }
                }
                
                await MainActor.run {
                    isProcessingEmbeddings = false
                    showAlert = true
                    alertMessage = "Successfully processed \(processedCount) out of \(totalCount) items."
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    isProcessingEmbeddings = false
                    showAlert = true
                    alertMessage = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
