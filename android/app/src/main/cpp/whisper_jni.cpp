// JNI wrapper for whisper.cpp (offline speech-to-text)
//
// This is designed to be optional:
// - If external/whisper.cpp is present, we compile against whisper.cpp and provide real STT.
// - If not present, we still build a stub libwhisper.so so the app compiles,
//   and `isAvailable()` returns false with clear error messages.

#include <jni.h>
#include <string>
#include <vector>
#include <android/log.h>

#define LOG_TAG "WhisperJNI"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

#if __has_include("whisper.h")
  #include "whisper.h"
  #define HAS_WHISPER 1
#else
  #define HAS_WHISPER 0
#endif

#if HAS_WHISPER
static whisper_context * g_wctx = nullptr;
#else
static void * g_wctx = nullptr;
#endif

static int g_threads = 4;

static std::vector<float> pcm16_to_f32(const int16_t * pcm, int n) {
    std::vector<float> out;
    out.resize(n);
    constexpr float k = 1.0f / 32768.0f;
    for (int i = 0; i < n; i++) out[i] = (float) pcm[i] * k;
    return out;
}

#if HAS_WHISPER
struct stream_callback_ctx {
    JNIEnv * env;
    jobject callback_obj;
    jmethodID mid_onPartial;
    std::string accumulated;
};

static void on_new_segment_cb(whisper_context * ctx, whisper_state * /*state*/, int n_new, void * user_data) {
    auto * cb = (stream_callback_ctx *) user_data;
    if (cb == nullptr || cb->env == nullptr || cb->callback_obj == nullptr || cb->mid_onPartial == nullptr) {
        return;
    }

    const int n_segments = whisper_full_n_segments(ctx);
    const int start = std::max(0, n_segments - n_new);
    for (int i = start; i < n_segments; i++) {
        const char * text = whisper_full_get_segment_text(ctx, i);
        if (text) cb->accumulated.append(text);
    }

    jstring jtxt = cb->env->NewStringUTF(cb->accumulated.c_str());
    cb->env->CallVoidMethod(cb->callback_obj, cb->mid_onPartial, jtxt);
    cb->env->DeleteLocalRef(jtxt);
}
#endif

extern "C" {

JNIEXPORT jboolean JNICALL
Java_com_microllm_app_WhisperNative_isAvailable(JNIEnv *, jclass) {
#if HAS_WHISPER
    return JNI_TRUE;
#else
    return JNI_FALSE;
#endif
}

JNIEXPORT jboolean JNICALL
Java_com_microllm_app_WhisperNative_loadModel(
        JNIEnv * env,
        jclass,
        jstring modelPath,
        jint threads) {
#if !HAS_WHISPER
    (void) env; (void) modelPath; (void) threads;
    LOGE("whisper.cpp not compiled in (missing whisper.h)");
    return JNI_FALSE;
#else
    if (g_wctx != nullptr) {
        whisper_free(g_wctx);
        g_wctx = nullptr;
    }

    const char * path = env->GetStringUTFChars(modelPath, nullptr);
    LOGI("Loading whisper model from: %s", path);
    g_threads = (int) threads;

    g_wctx = whisper_init_from_file(path);
    env->ReleaseStringUTFChars(modelPath, path);

    if (g_wctx == nullptr) {
        LOGE("Failed to init whisper context");
        return JNI_FALSE;
    }

    return JNI_TRUE;
#endif
}

JNIEXPORT void JNICALL
Java_com_microllm_app_WhisperNative_unloadModel(JNIEnv *, jclass) {
#if HAS_WHISPER
    if (g_wctx) {
        whisper_free(g_wctx);
        g_wctx = nullptr;
    }
#else
    g_wctx = nullptr;
#endif
}

JNIEXPORT jboolean JNICALL
Java_com_microllm_app_WhisperNative_isLoaded(JNIEnv *, jclass) {
    return g_wctx != nullptr ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jstring JNICALL
Java_com_microllm_app_WhisperNative_transcribePcm16(
        JNIEnv * env,
        jclass,
        jshortArray pcm16,
        jint sampleRate,
        jstring languageTag,
        jboolean translateToEnglish) {
#if !HAS_WHISPER
    (void) env; (void) pcm16; (void) sampleRate; (void) languageTag; (void) translateToEnglish;
    return nullptr;
#else
    if (g_wctx == nullptr) {
        LOGE("transcribe called but model not loaded");
        return nullptr;
    }

    const jsize n = env->GetArrayLength(pcm16);
    if (n <= 0) {
        return env->NewStringUTF("");
    }

    jboolean isCopy = JNI_FALSE;
    auto * pcm_ptr = (int16_t *) env->GetShortArrayElements(pcm16, &isCopy);
    std::vector<float> audio = pcm16_to_f32(pcm_ptr, (int) n);
    env->ReleaseShortArrayElements(pcm16, (jshort *) pcm_ptr, JNI_ABORT);

    // Whisper expects 16 kHz audio. If sampleRate differs, we currently reject.
    // (We downsample in Kotlin before calling into native.)
    if ((int) sampleRate != 16000) {
        LOGE("Expected 16000 Hz audio, got %d", (int) sampleRate);
        return nullptr;
    }

    whisper_full_params params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    params.n_threads = g_threads;
    params.translate = translateToEnglish == JNI_TRUE;
    params.print_progress = false;
    params.print_realtime = false;
    params.print_timestamps = false;

    const char * lang = env->GetStringUTFChars(languageTag, nullptr);
    // languageTag is BCP-47 (e.g., "es-ES"). whisper.cpp expects ISO-639-1 like "es".
    // We pass just the base language part.
    std::string langStr = lang ? std::string(lang) : std::string("en");
    env->ReleaseStringUTFChars(languageTag, lang);
    const auto dash = langStr.find('-');
    if (dash != std::string::npos) langStr = langStr.substr(0, dash);
    params.language = langStr.c_str();

    const int res = whisper_full(g_wctx, params, audio.data(), (int) audio.size());
    if (res != 0) {
        LOGE("whisper_full failed: %d", res);
        return nullptr;
    }

    const int n_segments = whisper_full_n_segments(g_wctx);
    std::string out;
    out.reserve(256);
    for (int i = 0; i < n_segments; i++) {
        const char * text = whisper_full_get_segment_text(g_wctx, i);
        if (text) out.append(text);
    }

    return env->NewStringUTF(out.c_str());
#endif
}

JNIEXPORT jstring JNICALL
Java_com_microllm_app_WhisperNative_transcribePcm16Streaming(
        JNIEnv * env,
        jclass,
        jshortArray pcm16,
        jint sampleRate,
        jstring languageTag,
        jboolean translateToEnglish,
        jobject callbackObj) {
#if !HAS_WHISPER
    (void) env; (void) pcm16; (void) sampleRate; (void) languageTag; (void) translateToEnglish; (void) callbackObj;
    return nullptr;
#else
    if (g_wctx == nullptr) {
        LOGE("transcribeStreaming called but model not loaded");
        return nullptr;
    }

    const jsize n = env->GetArrayLength(pcm16);
    if (n <= 0) {
        return env->NewStringUTF("");
    }

    jboolean isCopy = JNI_FALSE;
    auto * pcm_ptr = (int16_t *) env->GetShortArrayElements(pcm16, &isCopy);
    std::vector<float> audio = pcm16_to_f32(pcm_ptr, (int) n);
    env->ReleaseShortArrayElements(pcm16, (jshort *) pcm_ptr, JNI_ABORT);

    if ((int) sampleRate != 16000) {
        LOGE("Expected 16000 Hz audio, got %d", (int) sampleRate);
        return nullptr;
    }

    whisper_full_params params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    params.n_threads = g_threads;
    params.translate = translateToEnglish == JNI_TRUE;
    params.print_progress = false;
    params.print_realtime = false;
    params.print_timestamps = false;

    const char * lang = env->GetStringUTFChars(languageTag, nullptr);
    std::string langStr = lang ? std::string(lang) : std::string("en");
    env->ReleaseStringUTFChars(languageTag, lang);
    const auto dash = langStr.find('-');
    if (dash != std::string::npos) langStr = langStr.substr(0, dash);
    params.language = langStr.c_str();

    stream_callback_ctx cb{};
    if (callbackObj != nullptr) {
        jclass cbCls = env->GetObjectClass(callbackObj);
        // Kotlin object is expected to have: fun onPartial(text: String)
        jmethodID mid = env->GetMethodID(cbCls, "onPartial", "(Ljava/lang/String;)V");
        cb.env = env;
        cb.callback_obj = callbackObj;
        cb.mid_onPartial = mid;
        cb.accumulated.reserve(256);
        params.new_segment_callback = on_new_segment_cb;
        params.new_segment_callback_user_data = &cb;
    }

    const int res = whisper_full(g_wctx, params, audio.data(), (int) audio.size());
    if (res != 0) {
        LOGE("whisper_full failed: %d", res);
        return nullptr;
    }

    // Final aggregated text
    const int n_segments = whisper_full_n_segments(g_wctx);
    std::string out;
    out.reserve(256);
    for (int i = 0; i < n_segments; i++) {
        const char * text = whisper_full_get_segment_text(g_wctx, i);
        if (text) out.append(text);
    }

    return env->NewStringUTF(out.c_str());
#endif
}

} // extern "C"

