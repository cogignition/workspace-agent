import Foundation
import LocalLLMClient
import LocalLLMClientLlama

/// Wraps LocalLLMClient (llama.cpp backend) for structured inference with Gemma 4.
/// All inference runs on-device — zero API cost.
///
/// The engine is long-lived — created once at app launch and stored on AppState.
/// After each generation, a configurable unload timer starts. If no new generation
/// arrives before it fires, the model is released to free ~12GB RAM. Set timeout
/// to 0 for immediate unload (cron / single-shot mode).
///
/// The engine does NOT hold AppState — the caller (@MainActor EmailTriageService)
/// is responsible for updating UI state before/after calls.
actor InferenceEngine {
    private var client: AnyLLMClient?
    private var unloadTask: Task<Void, Never>?
    private(set) var isLoaded: Bool = false

    // MARK: - Lifecycle

    /// Load the GGUF model from disk into memory.
    /// On an M3 Pro 36GB, Gemma 4 12B Q8 takes ~12GB and loads in ~15 seconds.
    func loadModel(at path: String) async throws {
        // Cancel any pending unload — we're loading fresh
        unloadTask?.cancel()
        unloadTask = nil

        // Skip if already loaded
        if client != nil {
            isLoaded = true
            return
        }

        let modelURL = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            throw InferenceError.modelNotFound(path)
        }

        do {
            let llmClient = try await LocalLLMClient.llama(
                url: modelURL,
                parameter: .init(
                    context: 8192,       // Gemma 4 supports up to 128K but 8K is plenty for email triage
                    temperature: 0.3,    // Low temperature for structured output
                    topK: 40,
                    topP: 0.9,
                    options: .init(responseFormat: .json)
                )
            )
            self.client = AnyLLMClient(llmClient)
            isLoaded = true
        } catch {
            isLoaded = false
            throw InferenceError.loadFailed(error)
        }
    }

    /// Unload the model and free memory.
    func unload() {
        unloadTask?.cancel()
        unloadTask = nil
        client = nil
        isLoaded = false
    }

    // MARK: - Inference

    /// Callback type for streaming token progress updates.
    typealias ProgressCallback = @Sendable (Int) async -> Void

    /// Run a structured triage prompt against the loaded model.
    /// Returns the raw JSON string from the model for parsing by the caller.
    /// Optionally calls `onProgress` every 20 tokens with the current count.
    func generate(
        systemPrompt: String,
        userPrompt: String,
        unloadTimeout: TimeInterval = 300,
        onProgress: ProgressCallback? = nil
    ) async throws -> String {
        // Cancel any pending unload — we're about to use the model
        unloadTask?.cancel()
        unloadTask = nil

        guard let client else {
            throw InferenceError.modelNotLoaded
        }

        let input = LLMInput.chat([
            .system(systemPrompt),
            .user(userPrompt)
        ])

        var fullResponse = ""
        var tokenCount = 0

        do {
            for try await chunk in try await client.textStream(from: input) {
                fullResponse += chunk
                tokenCount += 1
                if tokenCount % 20 == 0 {
                    await onProgress?(tokenCount)
                }
            }
        } catch {
            throw InferenceError.generationFailed(error)
        }

        // Schedule auto-unload after the configured timeout
        scheduleUnload(after: unloadTimeout)

        return fullResponse
    }

    // MARK: - Auto-Unload Timer

    /// Schedule model unload after `timeout` seconds.
    /// If timeout is 0, unload immediately. Cancels any previously scheduled unload.
    private func scheduleUnload(after timeout: TimeInterval) {
        unloadTask?.cancel()

        if timeout <= 0 {
            // Immediate unload (cron / single-shot mode)
            unload()
            return
        }

        unloadTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(timeout))
                await self?.unload()
            } catch {
                // Task was cancelled — a new generate() call arrived, keep model loaded
            }
        }
    }

    // MARK: - Errors

    enum InferenceError: LocalizedError {
        case modelNotFound(String)
        case loadFailed(Error)
        case modelNotLoaded
        case generationFailed(Error)

        var errorDescription: String? {
            switch self {
            case .modelNotFound(let path): "Model file not found: \(path)"
            case .loadFailed(let e): "Failed to load model: \(e.localizedDescription)"
            case .modelNotLoaded: "No model loaded. Open Settings and set the model path."
            case .generationFailed(let e): "Generation failed: \(e.localizedDescription)"
            }
        }
    }
}
