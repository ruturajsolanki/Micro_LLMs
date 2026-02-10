package com.microllm.app

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * Handler for native llama.cpp operations on a background thread.
 * 
 * This uses the LlamaNative JNI bindings to call llama.cpp directly,
 * bypassing Dart FFI and its struct alignment issues.
 */
class LlamaHandler(private val context: Context) {
    
    companion object {
        private var initialized = false
        
        init {
            try {
                // LlamaNative loads the library in its init block
                LlamaNative.init()
                initialized = true
                android.util.Log.i("LlamaHandler", "llama backend initialized")
            } catch (e: Exception) {
                android.util.Log.e("LlamaHandler", "Failed to initialize llama: ${e.message}")
            }
        }
    }
    
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    // Incremental conversation buffer to avoid re-decoding the whole chat each turn.
    // This makes responses much faster and improves "memory retention" across turns.
    private val conversationBuffer = StringBuilder()
    private var conversationInitialized = false
    private var conversationLanguage = "English"

    // Pending conversation state captured before the model is loaded.
    //
    // Why:
    // - Flutter may call `setConversation` (and change target language) before a model is loaded.
    // - Previously, `setConversation` would fail with NOT_LOADED and we'd lose the language selection.
    // - We persist the desired language + messages here and apply them immediately after model load.
    private var pendingAssistantLanguage: String? = null
    private var pendingMessages: List<Map<String, Any?>> = emptyList()

    /**
     * Build a strong, model-friendly language constraint instruction.
     *
     * Why:
     * - Some models will drift to English if earlier history contains English.
     * - We reinforce the *latest* instruction by adding an additional system message
     *   at the end of `setConversation()` so the closest constraint wins.
     */
    private fun languageConstraint(language: String): String {
        val lang = language.ifBlank { "English" }
        return (
            "You are a helpful AI assistant.\n" +
                "IMPORTANT:\n" +
                "- You MUST respond in $lang only.\n" +
                "- Do NOT respond in any other language.\n" +
                "- If the user writes in a different language, translate internally and answer in $lang.\n" +
                "- Avoid mixing languages in the same response.\n"
            )
    }
    
    fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "loadModel" -> {
                val modelPath = call.argument<String>("modelPath")
                val contextSize = call.argument<Int>("contextSize") ?: 2048
                val threads = call.argument<Int>("threads") ?: 4
                
                if (modelPath == null) {
                    result.error("INVALID_ARGS", "Model path is required", null)
                    return
                }
                
                loadModelAsync(modelPath, contextSize, threads, result)
            }
            "unloadModel" -> {
                unloadModelAsync(result)
            }
            "isModelLoaded" -> {
                result.success(LlamaNative.isLoaded())
            }
            "getModelInfo" -> {
                if (!LlamaNative.isLoaded()) {
                    result.error("NOT_LOADED", "No model loaded", null)
                } else {
                    result.success(mapOf(
                        "isLoaded" to true,
                        "contextSize" to LlamaNative.getContextSize()
                    ))
                }
            }
            "tokenize" -> {
                val text = call.argument<String>("text") ?: ""
                val addBos = call.argument<Boolean>("addBos") ?: true
                tokenizeAsync(text, addBos, result)
            }
            "decode" -> {
                val tokens = call.argument<List<Int>>("tokens")
                if (tokens == null) {
                    result.error("INVALID_ARGS", "Tokens are required", null)
                    return
                }
                decodeAsync(tokens.toIntArray(), result)
            }
            "sample" -> {
                sampleAsync(result)
            }
            "tokenToString" -> {
                val token = call.argument<Int>("token") ?: 0
                result.success(LlamaNative.tokenToString(token))
            }
            "getEosToken" -> {
                result.success(LlamaNative.getEosToken())
            }
            "resetSampler" -> {
                val temperature = (call.argument<Double>("temperature") ?: 0.7).toFloat()
                val topP = (call.argument<Double>("topP") ?: 0.9).toFloat()
                val topK = call.argument<Int>("topK") ?: 40
                LlamaNative.resetSampler(temperature, topP, topK)
                result.success(true)
            }
            "clearContext" -> {
                LlamaNative.clearContext()
                result.success(true)
            }
            "resetConversation" -> {
                // Clears both native KV cache and the incremental prompt buffer.
                executor.execute {
                    try {
                        LlamaNative.clearContext()
                        conversationBuffer.clear()
                        conversationInitialized = false
                        mainHandler.post { result.success(true) }
                    } catch (e: Exception) {
                        mainHandler.post { result.error("RESET_FAILED", e.message, null) }
                    }
                }
            }
            "setConversation" -> {
                val assistantLanguage = call.argument<String>("assistantLanguage") ?: "English"
                val messages = call.argument<List<Map<String, Any?>>>("messages") ?: emptyList()
                setConversationAsync(assistantLanguage, messages, result)
            }
            "generate" -> {
                val prompt = call.argument<String>("prompt") ?: ""
                val maxTokens = call.argument<Int>("maxTokens") ?: 256
                val temperature = (call.argument<Double>("temperature") ?: 0.7).toFloat()
                val topP = (call.argument<Double>("topP") ?: 0.9).toFloat()
                val topK = call.argument<Int>("topK") ?: 40
                generateAsync(prompt, maxTokens, temperature, topP, topK, result)
            }
            "generateStateless" -> {
                val prompt = call.argument<String>("prompt") ?: ""
                val systemPrompt = call.argument<String>("systemPrompt")
                val stopSequences = call.argument<List<String>>("stopSequences") ?: emptyList()
                val maxTokens = call.argument<Int>("maxTokens") ?: 256
                val temperature = (call.argument<Double>("temperature") ?: 0.3).toFloat()
                val topP = (call.argument<Double>("topP") ?: 0.9).toFloat()
                val topK = call.argument<Int>("topK") ?: 40
                generateStatelessAsync(
                    prompt = prompt,
                    systemPrompt = systemPrompt,
                    stopSequences = stopSequences,
                    maxTokens = maxTokens,
                    temperature = temperature,
                    topP = topP,
                    topK = topK,
                    result = result
                )
            }
            else -> {
                result.notImplemented()
            }
        }
    }
    
    /**
     * Stateless generation that does NOT pollute the chat KV cache.
     *
     * Why:
     * - Translation prompts must be independent and deterministic.
     * - Chat history (often English) degrades translation quality.
     * - We snapshot + restore the incremental conversation buffer and KV cache.
     */
    private fun generateStatelessAsync(
        prompt: String,
        systemPrompt: String?,
        stopSequences: List<String>,
        maxTokens: Int,
        temperature: Float,
        topP: Float,
        topK: Int,
        result: MethodChannel.Result
    ) {
        executor.execute {
            if (!LlamaNative.isLoaded()) {
                mainHandler.post { result.error("NOT_LOADED", "No model loaded", null) }
                return@execute
            }

            // Snapshot current chat state (buffer + metadata)
            val snapshotBuffer = conversationBuffer.toString()
            val snapshotInitialized = conversationInitialized
            val snapshotLanguage = conversationLanguage
            val snapshotPendingLang = pendingAssistantLanguage
            val snapshotPendingMsgs = pendingMessages

            try {
                // Reset sampler with request params
                LlamaNative.resetSampler(temperature, topP, topK)

                // Isolated prompt buffer (ChatML)
                LlamaNative.clearContext()
                val iso = StringBuilder()
                iso.append("<|im_start|>system\n")
                iso.append(systemPrompt?.trim()?.ifEmpty { null } ?: "You are a helpful AI assistant.\n")
                iso.append("<|im_end|>\n")
                iso.append("<|im_start|>user\n")
                iso.append(prompt.trim()).append("\n")
                iso.append("<|im_end|>\n")
                iso.append("<|im_start|>assistant\n")

                val tokens = LlamaNative.tokenize(iso.toString(), true)
                if (tokens == null) {
                    mainHandler.post { result.error("TOKENIZE_FAILED", "Failed to tokenize stateless prompt", null) }
                    return@execute
                }
                val decodeResult = LlamaNative.decode(tokens)
                if (decodeResult != 0) {
                    mainHandler.post { result.error("DECODE_FAILED", "Failed to decode stateless prompt: $decodeResult", null) }
                    return@execute
                }

                val eosToken = LlamaNative.getEosToken()
                val generated = StringBuilder()
                var count = 0

                while (count < maxTokens) {
                    val token = LlamaNative.sample()
                    if (token < 0) break

                    val isEos = token == eosToken || token == 151643 || token == 151645
                    if (isEos) break

                    val tokenStr = LlamaNative.tokenToString(token)
                    generated.append(tokenStr)

                    // Stop sequence trimming (best-effort, prevents extra chatter for translation)
                    val genStr = generated.toString()
                    val stopHit = stopSequences.firstOrNull { it.isNotEmpty() && genStr.contains(it) }
                    if (stopHit != null) {
                        val idx = genStr.indexOf(stopHit)
                        if (idx >= 0) {
                            generated.setLength(idx)
                        }
                        break
                    }

                    val nextResult = LlamaNative.decode(intArrayOf(token))
                    if (nextResult != 0) break
                    count++
                }

                mainHandler.post {
                    result.success(
                        mapOf(
                            "text" to generated.toString(),
                            "tokenCount" to count,
                            "promptTokens" to tokens.size
                        )
                    )
                }
            } catch (e: Exception) {
                android.util.Log.e("LlamaHandler", "generateStateless failed", e)
                mainHandler.post { result.error("GENERATE_STATELESS_FAILED", e.message, e.stackTraceToString()) }
            } finally {
                // Restore chat state (buffer + KV cache) so translation never affects conversation memory.
                try {
                    conversationBuffer.clear()
                    conversationBuffer.append(snapshotBuffer)
                    conversationInitialized = snapshotInitialized
                    conversationLanguage = snapshotLanguage
                    pendingAssistantLanguage = snapshotPendingLang
                    pendingMessages = snapshotPendingMsgs

                    LlamaNative.clearContext()
                    if (snapshotInitialized && snapshotBuffer.isNotBlank()) {
                        val restoreTokens = LlamaNative.tokenize(snapshotBuffer, true)
                        if (restoreTokens != null) {
                            val restoreRes = LlamaNative.decode(restoreTokens)
                            if (restoreRes != 0) {
                                android.util.Log.w("LlamaHandler", "Restore decode failed: $restoreRes")
                            }
                        } else {
                            android.util.Log.w("LlamaHandler", "Restore tokenize failed")
                        }
                    }
                } catch (e: Exception) {
                    android.util.Log.w("LlamaHandler", "Failed to restore chat state after stateless generation: ${e.message}")
                }
            }
        }
    }

    private fun loadModelAsync(
        modelPath: String,
        contextSize: Int,
        threads: Int,
        result: MethodChannel.Result
    ) {
        val file = File(modelPath)
        if (!file.exists()) {
            result.error("FILE_NOT_FOUND", "Model file not found: $modelPath", null)
            return
        }
        
        val fileSize = file.length()
        android.util.Log.i("LlamaHandler", "Loading model: $modelPath (${fileSize / 1024 / 1024}MB)")
        
        executor.execute {
            try {
                val startTime = System.currentTimeMillis()
                
                val success = LlamaNative.loadModel(modelPath, contextSize, threads)
                
                val elapsed = System.currentTimeMillis() - startTime
                android.util.Log.i("LlamaHandler", "Model loading completed in ${elapsed}ms, success=$success")
                
                mainHandler.post {
                    if (success) {
                        // Reset conversation state when model changes
                        conversationBuffer.clear()
                        conversationInitialized = false

                        // Apply any pending conversation (language + messages) captured before load.
                        // This ensures the system prompt uses the correct target language even if
                        // the user changed it on the loading screen.
                        try {
                            applyPendingConversationIfAny()
                        } catch (e: Exception) {
                            android.util.Log.w("LlamaHandler", "Failed to apply pending conversation: ${e.message}")
                        }

                        result.success(mapOf(
                            "success" to true,
                            "contextSize" to LlamaNative.getContextSize(),
                            "loadTimeMs" to elapsed,
                            "fileSizeBytes" to fileSize
                        ))
                    } else {
                        result.error("LOAD_FAILED", "Failed to load model", null)
                    }
                }
            } catch (e: Exception) {
                android.util.Log.e("LlamaHandler", "Model loading failed", e)
                mainHandler.post {
                    result.error("LOAD_EXCEPTION", e.message, e.stackTraceToString())
                }
            }
        }
    }
    
    private fun unloadModelAsync(result: MethodChannel.Result) {
        executor.execute {
            try {
                LlamaNative.unloadModel()
                conversationBuffer.clear()
                conversationInitialized = false
                // Keep pending state cleared when explicitly unloading a model.
                pendingAssistantLanguage = null
                pendingMessages = emptyList()
                mainHandler.post {
                    result.success(true)
                }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error("UNLOAD_FAILED", e.message, null)
                }
            }
        }
    }
    
    private fun tokenizeAsync(text: String, addBos: Boolean, result: MethodChannel.Result) {
        executor.execute {
            try {
                val tokens = LlamaNative.tokenize(text, addBos)
                mainHandler.post {
                    if (tokens != null) {
                        result.success(tokens.toList())
                    } else {
                        result.error("TOKENIZE_FAILED", "Failed to tokenize", null)
                    }
                }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error("TOKENIZE_EXCEPTION", e.message, null)
                }
            }
        }
    }
    
    private fun decodeAsync(tokens: IntArray, result: MethodChannel.Result) {
        executor.execute {
            try {
                val decodeResult = LlamaNative.decode(tokens)
                mainHandler.post {
                    result.success(decodeResult)
                }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error("DECODE_EXCEPTION", e.message, null)
                }
            }
        }
    }
    
    private fun sampleAsync(result: MethodChannel.Result) {
        executor.execute {
            try {
                val token = LlamaNative.sample()
                mainHandler.post {
                    result.success(token)
                }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error("SAMPLE_EXCEPTION", e.message, null)
                }
            }
        }
    }
    
    private fun generateAsync(
        prompt: String,
        maxTokens: Int,
        temperature: Float,
        topP: Float,
        topK: Int,
        result: MethodChannel.Result
    ) {
        executor.execute {
            try {
                // Reset sampler with generation params
                LlamaNative.resetSampler(temperature, topP, topK)

                android.util.Log.i(
                    "LlamaHandler",
                    "Generate called. conversationInitialized=$conversationInitialized, language=$conversationLanguage, pendingLang=${pendingAssistantLanguage ?: "none"}"
                )

                // Initialize conversation once per session (keeps memory across turns)
                if (!conversationInitialized) {
                    // Clear native context once at the beginning of a new chat session
                    LlamaNative.clearContext()
                    // Use Qwen ChatML format with explicit language constraint
                    if (conversationLanguage.isBlank()) {
                        conversationLanguage = "English"
                    }
                    conversationBuffer.append("<|im_start|>system\\n")
                    conversationBuffer.append(languageConstraint(conversationLanguage))
                    conversationBuffer.append("<|im_end|>\\n")
                    conversationInitialized = true
                }

                // Append only the new user turn (incremental prompting)
                val appended = StringBuilder()
                appended.append("<|im_start|>user\\n")
                appended.append(prompt.trim()).append("\\n")
                appended.append("<|im_end|>\\n")
                appended.append("<|im_start|>assistant\\n")

                // Update our running buffer first
                conversationBuffer.append(appended)

                // Tokenize only what we appended (no BOS for incremental chunks)
                val tokens = LlamaNative.tokenize(appended.toString(), false)
                if (tokens == null) {
                    mainHandler.post {
                        result.error("TOKENIZE_FAILED", "Failed to tokenize prompt", null)
                    }
                    return@execute
                }
                
                android.util.Log.i("LlamaHandler", "Processing ${tokens.size} prompt tokens")
                
                // Decode prompt tokens
                val decodeResult = LlamaNative.decode(tokens)
                if (decodeResult != 0) {
                    mainHandler.post {
                        result.error("DECODE_FAILED", "Failed to decode prompt: $decodeResult", null)
                    }
                    return@execute
                }
                
                // Generate tokens
                val eosToken = LlamaNative.getEosToken()
                val generated = StringBuilder()
                var count = 0
                
                android.util.Log.i("LlamaHandler", "Generating up to $maxTokens tokens, EOS=$eosToken")
                
                while (count < maxTokens) {
                    val token = LlamaNative.sample()

                    if (token < 0) {
                        android.util.Log.e("LlamaHandler", "Sample returned error token: $token")
                        break
                    }
                    
                    // Check for various EOS tokens
                    // Qwen2.5: 151643 (<|endoftext|>), 151645 (<|im_end|>)
                    val isEos = token == eosToken || token == 151643 || token == 151645
                    
                    if (isEos) {
                        android.util.Log.i("LlamaHandler", "Hit EOS token $token at $count")
                        break
                    }
                    
                    val tokenStr = LlamaNative.tokenToString(token)
                    generated.append(tokenStr)
                    
                    // Decode the new token for next iteration
                    val singleToken = intArrayOf(token)
                    val nextResult = LlamaNative.decode(singleToken)
                    if (nextResult != 0) {
                        android.util.Log.e("LlamaHandler", "Decode failed at token $count: $nextResult")
                        break
                    }
                    
                    count++
                }
                
                android.util.Log.i("LlamaHandler", "Generated $count tokens")

                // Persist assistant output into the running conversation buffer
                conversationBuffer.append(generated.toString()).append("\\n<|im_end|>\\n")
                
                mainHandler.post {
                    result.success(mapOf(
                        "text" to generated.toString(),
                        "tokenCount" to count,
                        "promptTokens" to tokens.size
                    ))
                }
            } catch (e: Exception) {
                android.util.Log.e("LlamaHandler", "Generate failed", e)
                mainHandler.post {
                    result.error("GENERATE_EXCEPTION", e.message, e.stackTraceToString())
                }
            }
        }
    }
    
    fun destroy() {
        executor.execute {
            LlamaNative.unloadModel()
        }
        executor.shutdown()
    }

    private fun setConversationAsync(
        assistantLanguage: String,
        messages: List<Map<String, Any?>>,
        result: MethodChannel.Result
    ) {
        executor.execute {
            try {
                // Always remember desired assistant language + messages, even if no model is loaded yet.
                // This prevents losing the user's selection during startup.
                pendingAssistantLanguage = assistantLanguage.ifBlank { "English" }
                pendingMessages = messages

                android.util.Log.i(
                    "LlamaHandler",
                    "setConversation requested. loaded=${LlamaNative.isLoaded()}, assistantLanguage=$assistantLanguage, messages=${messages.size}"
                )

                if (!LlamaNative.isLoaded()) {
                    // Not an error: we'll apply this immediately after the model is loaded.
                    conversationLanguage = pendingAssistantLanguage ?: "English"
                    conversationBuffer.clear()
                    conversationInitialized = false
                    mainHandler.post {
                        result.success(
                            mapOf(
                                "success" to true,
                                "pending" to true,
                                "promptTokens" to 0
                            )
                        )
                    }
                    return@execute
                }

                // Reset native state + buffer
                LlamaNative.clearContext()
                conversationBuffer.clear()
                conversationInitialized = false

                conversationLanguage = assistantLanguage.ifBlank { "English" }

                // System prompt
                conversationBuffer.append("<|im_start|>system\\n")
                conversationBuffer.append(languageConstraint(conversationLanguage))
                conversationBuffer.append("<|im_end|>\\n")

                // Replay history (user/assistant)
                for (m in messages) {
                    val role = (m["role"] as String?) ?: continue
                    val content = (m["content"] as String?) ?: ""
                    if (content.isBlank()) continue

                    when (role) {
                        "user" -> {
                            conversationBuffer.append("<|im_start|>user\\n")
                            conversationBuffer.append(content.trim()).append("\\n")
                            conversationBuffer.append("<|im_end|>\\n")
                        }
                        "assistant" -> {
                            conversationBuffer.append("<|im_start|>assistant\\n")
                            conversationBuffer.append(content.trim()).append("\\n")
                            conversationBuffer.append("<|im_end|>\\n")
                        }
                    }
                }

                // Reinforce language constraint at the end so it overrides older turns
                // (especially important when user changes target language mid-chat).
                conversationBuffer.append("<|im_start|>system\\n")
                conversationBuffer.append(
                    "Reminder: All future assistant replies must be in $conversationLanguage only.\n"
                )
                conversationBuffer.append("<|im_end|>\\n")

                // Tokenize + decode full buffer into KV cache (with BOS once)
                val tokens = LlamaNative.tokenize(conversationBuffer.toString(), true)
                if (tokens == null) {
                    mainHandler.post { result.error("TOKENIZE_FAILED", "Failed to tokenize conversation", null) }
                    return@execute
                }
                val decodeResult = LlamaNative.decode(tokens)
                if (decodeResult != 0) {
                    mainHandler.post { result.error("DECODE_FAILED", "Failed to decode conversation: $decodeResult", null) }
                    return@execute
                }

                conversationInitialized = true
                mainHandler.post {
                    result.success(
                        mapOf(
                            "success" to true,
                            "promptTokens" to tokens.size
                        )
                    )
                }
            } catch (e: Exception) {
                android.util.Log.e("LlamaHandler", "setConversation failed", e)
                mainHandler.post { result.error("SET_CONVERSATION_FAILED", e.message, e.stackTraceToString()) }
            }
        }
    }

    /**
     * Apply pending conversation (language + messages) into the KV cache.
     *
     * Must be called on the executor thread.
     */
    private fun applyPendingConversationIfAny() {
        if (!LlamaNative.isLoaded()) return
        val lang = pendingAssistantLanguage?.ifBlank { "English" } ?: return
        val msgs = pendingMessages

        android.util.Log.i(
            "LlamaHandler",
            "Applying pending conversation after model load. language=$lang, messages=${msgs.size}"
        )

        // Reuse the existing setConversation logic, but without posting results.
        LlamaNative.clearContext()
        conversationBuffer.clear()
        conversationInitialized = false
        conversationLanguage = lang

        // System prompt
        conversationBuffer.append("<|im_start|>system\\n")
        conversationBuffer.append(languageConstraint(conversationLanguage))
        conversationBuffer.append("<|im_end|>\\n")

        // Replay history (user/assistant)
        for (m in msgs) {
            val role = (m["role"] as String?) ?: continue
            val content = (m["content"] as String?) ?: ""
            if (content.isBlank()) continue

            when (role) {
                "user" -> {
                    conversationBuffer.append("<|im_start|>user\\n")
                    conversationBuffer.append(content.trim()).append("\\n")
                    conversationBuffer.append("<|im_end|>\\n")
                }
                "assistant" -> {
                    conversationBuffer.append("<|im_start|>assistant\\n")
                    conversationBuffer.append(content.trim()).append("\\n")
                    conversationBuffer.append("<|im_end|>\\n")
                }
            }
        }

        // Reinforce at the end (same as setConversationAsync)
        conversationBuffer.append("<|im_start|>system\\n")
        conversationBuffer.append(
            "Reminder: All future assistant replies must be in $conversationLanguage only.\n"
        )
        conversationBuffer.append("<|im_end|>\\n")

        val tokens = LlamaNative.tokenize(conversationBuffer.toString(), true)
        if (tokens == null) {
            android.util.Log.w("LlamaHandler", "Pending conversation tokenize failed")
            conversationInitialized = true // at least keep language for next init
            return
        }
        val decodeResult = LlamaNative.decode(tokens)
        if (decodeResult != 0) {
            android.util.Log.w("LlamaHandler", "Pending conversation decode failed: $decodeResult")
            conversationInitialized = true
            return
        }

        conversationInitialized = true
    }
}
