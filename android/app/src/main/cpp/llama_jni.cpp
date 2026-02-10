// JNI wrapper for llama.cpp
// This handles all struct construction natively to avoid FFI alignment issues

#include <jni.h>
#include <string>
#include <vector>
#include <cstring>
#include <android/log.h>
#include "llama.h"

#define LOG_TAG "LlamaJNI"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// Convert raw bytes into a Java String safely.
//
// Why:
// - llama_token_to_piece may return byte sequences that are not valid "Modified UTF-8".
// - JNI NewStringUTF() requires Modified UTF-8 and will hard-abort the process if invalid.
// - Constructing String(byte[], UTF_8) tolerates invalid sequences and replaces them (U+FFFD),
//   preventing fatal JNI aborts on multilingual output.
static jstring new_string_from_utf8_bytes(JNIEnv* env, const char* bytes, int len) {
    if (bytes == nullptr || len <= 0) {
        return env->NewStringUTF("");
    }

    jbyteArray arr = env->NewByteArray(len);
    if (arr == nullptr) {
        // OOM: best-effort fallback
        return env->NewStringUTF("");
    }
    env->SetByteArrayRegion(arr, 0, len, reinterpret_cast<const jbyte*>(bytes));

    // Get StandardCharsets.UTF_8
    jclass scClass = env->FindClass("java/nio/charset/StandardCharsets");
    if (scClass == nullptr) {
        env->DeleteLocalRef(arr);
        return env->NewStringUTF("");
    }
    jfieldID utf8Field = env->GetStaticFieldID(scClass, "UTF_8", "Ljava/nio/charset/Charset;");
    if (utf8Field == nullptr) {
        env->DeleteLocalRef(scClass);
        env->DeleteLocalRef(arr);
        return env->NewStringUTF("");
    }
    jobject utf8Charset = env->GetStaticObjectField(scClass, utf8Field);
    if (utf8Charset == nullptr) {
        env->DeleteLocalRef(scClass);
        env->DeleteLocalRef(arr);
        return env->NewStringUTF("");
    }

    // new String(byte[], Charset)
    jclass strClass = env->FindClass("java/lang/String");
    if (strClass == nullptr) {
        env->DeleteLocalRef(utf8Charset);
        env->DeleteLocalRef(scClass);
        env->DeleteLocalRef(arr);
        return env->NewStringUTF("");
    }
    jmethodID ctor = env->GetMethodID(strClass, "<init>", "([BLjava/nio/charset/Charset;)V");
    if (ctor == nullptr) {
        env->DeleteLocalRef(strClass);
        env->DeleteLocalRef(utf8Charset);
        env->DeleteLocalRef(scClass);
        env->DeleteLocalRef(arr);
        return env->NewStringUTF("");
    }

    jobject strObj = env->NewObject(strClass, ctor, arr, utf8Charset);
    jstring out = (jstring) strObj;

    // Clean up locals (String object returned remains valid as `out`)
    env->DeleteLocalRef(strClass);
    env->DeleteLocalRef(utf8Charset);
    env->DeleteLocalRef(scClass);
    env->DeleteLocalRef(arr);

    if (env->ExceptionCheck()) {
        env->ExceptionClear();
        return env->NewStringUTF("");
    }

    return out != nullptr ? out : env->NewStringUTF("");
}

// Global state (single model instance)
static llama_model* g_model = nullptr;
static llama_context* g_ctx = nullptr;
static llama_sampler* g_sampler = nullptr;
static int32_t g_n_past = 0; // current position in KV cache (token index)

static int decode_tokens_internal(const llama_token * tokens, int32_t n_tokens) {
    if (g_ctx == nullptr) {
        return -1;
    }

    const int32_t n_batch = (int32_t) llama_n_batch(g_ctx);
    const int32_t seq_id = 0;

    int32_t offset = 0;
    while (offset < n_tokens) {
        const int32_t n_eval = std::min(n_batch, n_tokens - offset);

        llama_batch batch = llama_batch_init(n_eval, 0, 1);
        batch.n_tokens = n_eval;

        for (int32_t i = 0; i < n_eval; i++) {
            batch.token[i] = tokens[offset + i];
            batch.pos[i] = (llama_pos) (g_n_past + i);
            batch.n_seq_id[i] = 1;
            batch.seq_id[i][0] = seq_id;
            batch.logits[i] = 0;
        }

        // Only request logits for the last token of the *final* chunk.
        if (offset + n_eval == n_tokens) {
            batch.logits[n_eval - 1] = 1;
        }

        const int res = llama_decode(g_ctx, batch);
        llama_batch_free(batch);

        if (res != 0) {
            return res;
        }

        g_n_past += n_eval;
        offset += n_eval;
    }

    return 0;
}

extern "C" {

JNIEXPORT void JNICALL
Java_com_microllm_app_LlamaNative_init(JNIEnv* env, jclass clazz) {
    LOGI("Initializing llama backend");
    llama_backend_init();
}

JNIEXPORT jboolean JNICALL
Java_com_microllm_app_LlamaNative_loadModel(
    JNIEnv* env, 
    jclass clazz,
    jstring modelPath,
    jint contextSize,
    jint threads
) {
    if (g_model != nullptr) {
        LOGI("Unloading existing model first");
        if (g_sampler) {
            llama_sampler_free(g_sampler);
            g_sampler = nullptr;
        }
        if (g_ctx) {
            llama_free(g_ctx);
            g_ctx = nullptr;
        }
        llama_model_free(g_model);
        g_model = nullptr;
        g_n_past = 0;
    }

    const char* path = env->GetStringUTFChars(modelPath, nullptr);
    LOGI("Loading model from: %s", path);
    LOGI("Context size: %d, threads: %d", contextSize, threads);

    // Get default model params and customize
    llama_model_params model_params = llama_model_default_params();
    model_params.n_gpu_layers = 0;  // CPU only for mobile
    model_params.use_mmap = true;
    model_params.use_mlock = false;

    // Load model
    g_model = llama_model_load_from_file(path, model_params);
    env->ReleaseStringUTFChars(modelPath, path);

    if (g_model == nullptr) {
        LOGE("Failed to load model");
        return JNI_FALSE;
    }

    LOGI("Model loaded, creating context...");

    // Get default context params and customize
    llama_context_params ctx_params = llama_context_default_params();
    ctx_params.n_ctx = contextSize;
    ctx_params.n_batch = 512;
    ctx_params.n_ubatch = 512;
    ctx_params.n_threads = threads;
    ctx_params.n_threads_batch = threads;
    ctx_params.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_DISABLED;

    // Create context
    g_ctx = llama_init_from_model(g_model, ctx_params);

    if (g_ctx == nullptr) {
        LOGE("Failed to create context");
        llama_model_free(g_model);
        g_model = nullptr;
        return JNI_FALSE;
    }

    // Reset KV position for new model
    g_n_past = 0;

    LOGI("Context created, setting up sampler...");

    // Create sampler chain
    llama_sampler_chain_params chain_params = llama_sampler_chain_default_params();
    g_sampler = llama_sampler_chain_init(chain_params);

    // Add samplers: top-k -> top-p -> temp -> dist
    llama_sampler_chain_add(g_sampler, llama_sampler_init_top_k(40));
    llama_sampler_chain_add(g_sampler, llama_sampler_init_top_p(0.9f, 1));
    llama_sampler_chain_add(g_sampler, llama_sampler_init_temp(0.7f));
    llama_sampler_chain_add(g_sampler, llama_sampler_init_dist(42));

    LOGI("Model loading complete!");
    return JNI_TRUE;
}

JNIEXPORT void JNICALL
Java_com_microllm_app_LlamaNative_unloadModel(JNIEnv* env, jclass clazz) {
    LOGI("Unloading model");
    
    if (g_sampler) {
        llama_sampler_free(g_sampler);
        g_sampler = nullptr;
    }
    if (g_ctx) {
        llama_free(g_ctx);
        g_ctx = nullptr;
    }
    if (g_model) {
        llama_model_free(g_model);
        g_model = nullptr;
    }
    g_n_past = 0;
    
    LOGI("Model unloaded");
}

JNIEXPORT jboolean JNICALL
Java_com_microllm_app_LlamaNative_isLoaded(JNIEnv* env, jclass clazz) {
    return (g_model != nullptr && g_ctx != nullptr) ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jintArray JNICALL
Java_com_microllm_app_LlamaNative_tokenize(
    JNIEnv* env,
    jclass clazz,
    jstring text,
    jboolean addBos
) {
    if (g_model == nullptr) {
        LOGE("Model not loaded");
        return nullptr;
    }

    const char* textChars = env->GetStringUTFChars(text, nullptr);
    const llama_vocab* vocab = llama_model_get_vocab(g_model);
    
    // Estimate max tokens needed
    int maxTokens = strlen(textChars) + 16;
    std::vector<llama_token> tokens(maxTokens);

    int nTokens = llama_tokenize(vocab, textChars, strlen(textChars), 
                                  tokens.data(), maxTokens, addBos, true);
    
    env->ReleaseStringUTFChars(text, textChars);

    if (nTokens < 0) {
        LOGE("Tokenization failed");
        return nullptr;
    }

    // Create Java array
    jintArray result = env->NewIntArray(nTokens);
    env->SetIntArrayRegion(result, 0, nTokens, tokens.data());
    
    return result;
}

JNIEXPORT jint JNICALL
Java_com_microllm_app_LlamaNative_decode(
    JNIEnv* env,
    jclass clazz,
    jintArray tokens
) {
    if (g_ctx == nullptr) {
        LOGE("Context not loaded");
        return -1;
    }

    jsize nTokens = env->GetArrayLength(tokens);
    jint* tokenData = env->GetIntArrayElements(tokens, nullptr);

    // Decode with proper batch fields so logits are produced.
    // NOTE: llama_token is int32_t, jint is int32_t on Android.
    const int result = decode_tokens_internal(reinterpret_cast<llama_token *>(tokenData), (int32_t) nTokens);

    env->ReleaseIntArrayElements(tokens, tokenData, 0);
    
    return result;
}

JNIEXPORT jint JNICALL
Java_com_microllm_app_LlamaNative_sample(JNIEnv* env, jclass clazz) {
    if (g_ctx == nullptr || g_sampler == nullptr) {
        LOGE("Context or sampler not loaded");
        return -1;
    }

    llama_token token = llama_sampler_sample(g_sampler, g_ctx, -1);
    llama_sampler_accept(g_sampler, token);

    return token;
}

JNIEXPORT jstring JNICALL
Java_com_microllm_app_LlamaNative_tokenToString(
    JNIEnv* env,
    jclass clazz,
    jint token
) {
    if (g_model == nullptr) {
        return env->NewStringUTF("");
    }

    // Token pieces can be longer than 256 bytes for some vocabularies.
    // Use a bigger buffer to reduce truncation risk.
    std::vector<char> buf(4096);
    const llama_vocab* vocab = llama_model_get_vocab(g_model);
    int len = llama_token_to_piece(vocab, token, buf.data(), (int)buf.size(), 0, true);
    
    if (len < 0) {
        return env->NewStringUTF("");
    }

    // `len` is the number of bytes written (may include non-UTF8 bytes).
    // Do NOT use NewStringUTF here (it requires Modified UTF-8).
    return new_string_from_utf8_bytes(env, buf.data(), len);
}

JNIEXPORT jint JNICALL
Java_com_microllm_app_LlamaNative_getEosToken(JNIEnv* env, jclass clazz) {
    if (g_model == nullptr) {
        return 2; // Default EOS
    }
    const llama_vocab* vocab = llama_model_get_vocab(g_model);
    return llama_vocab_eos(vocab);
}

JNIEXPORT jint JNICALL
Java_com_microllm_app_LlamaNative_getContextSize(JNIEnv* env, jclass clazz) {
    if (g_ctx == nullptr) {
        return 0;
    }
    return llama_n_ctx(g_ctx);
}

JNIEXPORT void JNICALL
Java_com_microllm_app_LlamaNative_resetSampler(
    JNIEnv* env,
    jclass clazz,
    jfloat temperature,
    jfloat topP,
    jint topK
) {
    if (g_sampler) {
        llama_sampler_free(g_sampler);
    }

    llama_sampler_chain_params chain_params = llama_sampler_chain_default_params();
    g_sampler = llama_sampler_chain_init(chain_params);

    if (topK > 0) {
        llama_sampler_chain_add(g_sampler, llama_sampler_init_top_k(topK));
    }
    if (topP < 1.0f) {
        llama_sampler_chain_add(g_sampler, llama_sampler_init_top_p(topP, 1));
    }
    if (temperature > 0) {
        llama_sampler_chain_add(g_sampler, llama_sampler_init_temp(temperature));
        llama_sampler_chain_add(g_sampler, llama_sampler_init_dist(42));
    } else {
        llama_sampler_chain_add(g_sampler, llama_sampler_init_greedy());
    }
}

JNIEXPORT void JNICALL
Java_com_microllm_app_LlamaNative_clearContext(JNIEnv* env, jclass clazz) {
    if (g_ctx != nullptr) {
        llama_memory_t mem = llama_get_memory(g_ctx);
        if (mem != nullptr) {
            llama_memory_clear(mem, true);
        }
    }
    g_n_past = 0;
}

} // extern "C"
