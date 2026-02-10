package com.microllm.app

/**
 * Native JNI bindings to llama.cpp.
 * 
 * These methods call directly into C++ code, bypassing Dart FFI
 * and its struct alignment issues.
 */
object LlamaNative {
    
    init {
        try {
            System.loadLibrary("llama")
            android.util.Log.i("LlamaNative", "Loaded libllama.so")
        } catch (e: UnsatisfiedLinkError) {
            android.util.Log.e("LlamaNative", "Failed to load llama library: ${e.message}")
        }
    }

    /**
     * Initialize the llama backend. Call once at app start.
     */
    @JvmStatic
    external fun init()

    /**
     * Load a model from the given path.
     * @return true on success, false on failure
     */
    @JvmStatic
    external fun loadModel(modelPath: String, contextSize: Int, threads: Int): Boolean

    /**
     * Unload the current model and free all resources.
     */
    @JvmStatic
    external fun unloadModel()

    /**
     * Check if a model is currently loaded.
     */
    @JvmStatic
    external fun isLoaded(): Boolean

    /**
     * Tokenize text into token IDs.
     * @return array of token IDs, or null on failure
     */
    @JvmStatic
    external fun tokenize(text: String, addBos: Boolean): IntArray?

    /**
     * Decode tokens through the model.
     * @return 0 on success, negative on error
     */
    @JvmStatic
    external fun decode(tokens: IntArray): Int

    /**
     * Sample the next token from the model.
     * @return the sampled token ID
     */
    @JvmStatic
    external fun sample(): Int

    /**
     * Convert a token ID to its string representation.
     */
    @JvmStatic
    external fun tokenToString(token: Int): String

    /**
     * Get the end-of-sequence token ID.
     */
    @JvmStatic
    external fun getEosToken(): Int

    /**
     * Get the context size of the loaded model.
     */
    @JvmStatic
    external fun getContextSize(): Int

    /**
     * Reset the sampler with new parameters.
     */
    @JvmStatic
    external fun resetSampler(temperature: Float, topP: Float, topK: Int)

    /**
     * Clear the KV cache for a new conversation.
     */
    @JvmStatic
    external fun clearContext()
}
