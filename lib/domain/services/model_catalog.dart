import '../entities/device_specs.dart';

/// Catalog of available LLM models.
/// 
/// Contains all supported models with their specifications and requirements.
/// Models are sorted by size (smallest first) for easier selection.
/// 
/// All models use GGUF format compatible with llama.cpp.
/// Download URLs point to Hugging Face repositories.
class ModelCatalog {
  ModelCatalog._();
  
  /// All available models.
  static const List<ModelOption> models = [
    // SmolLM 135M - Extremely tiny, for testing
    ModelOption(
      id: 'smollm-135m-q8',
      name: 'SmolLM 135M',
      description: 'Extremely small model for basic testing. '
                   'Very fast but limited capabilities.',
      parameters: '135M',
      quantization: 'Q8_0',
      sizeBytes: 145 * 1024 * 1024, // ~145 MB
      minRamBytes: 512 * 1024 * 1024, // 512 MB
      recommendedRamBytes: 1024 * 1024 * 1024, // 1 GB
      contextSize: 2048,
      downloadUrl: 'https://huggingface.co/HuggingFaceTB/smollm-135M-instruct-v0.2-Q8_0-GGUF/resolve/main/smollm-135m-instruct-v0.2-q8_0.gguf',
      sha256: '',
      supportedLanguages: ['en'],
      strengths: ['Ultra fast', 'Tiny size', 'Good for testing'],
    ),
    
    // TinyLlama - Smallest practical option
    ModelOption(
      id: 'tinyllama-1.1b-q4',
      name: 'TinyLlama 1.1B',
      description: 'Ultra-lightweight model for basic conversations. '
                   'Best for low-end devices.',
      parameters: '1.1B',
      quantization: 'Q4_K_M',
      sizeBytes: 670 * 1024 * 1024, // ~670 MB
      minRamBytes: 2 * 1024 * 1024 * 1024, // 2 GB
      recommendedRamBytes: 3 * 1024 * 1024 * 1024, // 3 GB
      contextSize: 2048,
      downloadUrl: 'https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf',
      sha256: '',
      supportedLanguages: ['en'],
      strengths: ['Fast inference', 'Low memory', 'Quick responses'],
    ),
    
    // Qwen2.5 0.5B - Very small but capable
    ModelOption(
      id: 'qwen2.5-0.5b-q4',
      name: 'Qwen2.5 0.5B',
      description: 'Alibaba\'s latest small model. Excellent for its size '
                   'with good multilingual support.',
      parameters: '0.5B',
      quantization: 'Q4_K_M',
      sizeBytes: 400 * 1024 * 1024, // ~400 MB
      minRamBytes: 1 * 1024 * 1024 * 1024, // 1 GB
      recommendedRamBytes: 2 * 1024 * 1024 * 1024, // 2 GB
      contextSize: 4096,
      downloadUrl: 'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf',
      sha256: '',
      supportedLanguages: ['en', 'zh', 'ja', 'ko', 'es', 'fr', 'de'],
      strengths: ['Multilingual', 'Fast', 'Small size'],
    ),
    
    // Qwen2.5 1.5B - Good balance
    ModelOption(
      id: 'qwen2.5-1.5b-q4',
      name: 'Qwen2.5 1.5B',
      description: 'Excellent multilingual model with strong reasoning '
                   'and code capabilities.',
      parameters: '1.5B',
      quantization: 'Q4_K_M',
      sizeBytes: 1100 * 1024 * 1024, // ~1.1 GB
      minRamBytes: 2 * 1024 * 1024 * 1024, // 2 GB
      recommendedRamBytes: 3 * 1024 * 1024 * 1024, // 3 GB
      contextSize: 8192,
      downloadUrl: 'https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf',
      sha256: '',
      supportedLanguages: ['en', 'zh', 'ja', 'ko', 'es', 'fr', 'de', 'ru', 'ar'],
      strengths: ['Best multilingual', 'Good at code', 'Long context'],
    ),
    
    // Phi-3 Mini 3.8B - High quality
    ModelOption(
      id: 'phi3-mini-q4',
      name: 'Phi-3 Mini 3.8B',
      description: 'Microsoft\'s efficient model with excellent reasoning. '
                   'Best quality-to-size ratio.',
      parameters: '3.8B',
      quantization: 'Q4_K_M',
      sizeBytes: 2300 * 1024 * 1024, // ~2.3 GB
      minRamBytes: 4 * 1024 * 1024 * 1024, // 4 GB
      recommendedRamBytes: 6 * 1024 * 1024 * 1024, // 6 GB
      contextSize: 4096,
      downloadUrl: 'https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-gguf/resolve/main/Phi-3-mini-4k-instruct-q4.gguf',
      sha256: '',
      supportedLanguages: ['en'],
      strengths: ['Strong reasoning', 'Excellent quality', 'Efficient'],
    ),
    
    // Gemma 2 2B - Good quality small model
    ModelOption(
      id: 'gemma2-2b-q4',
      name: 'Gemma 2 2B',
      description: 'Google\'s latest small model with improved quality '
                   'and instruction following.',
      parameters: '2B',
      quantization: 'Q4_K_M',
      sizeBytes: 1600 * 1024 * 1024, // ~1.6 GB
      minRamBytes: 3 * 1024 * 1024 * 1024, // 3 GB
      recommendedRamBytes: 4 * 1024 * 1024 * 1024, // 4 GB
      contextSize: 8192,
      downloadUrl: 'https://huggingface.co/bartowski/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-Q4_K_M.gguf',
      sha256: '',
      supportedLanguages: ['en', 'es', 'fr', 'de', 'it', 'pt', 'nl', 'ru'],
      strengths: ['Good quality', 'Long context', 'Instruction following'],
    ),

    // Phi-2 2.7B - Original recommended model (~1.7 GB)
    ModelOption(
      id: 'phi2-2.7b-q4',
      name: 'Phi-2 2.7B',
      description: 'Microsoft\'s compact reasoning model. Strong English '
                   'instruction following with good quality for its size.',
      parameters: '2.7B',
      quantization: 'Q4_K_M',
      sizeBytes: 1700 * 1024 * 1024, // ~1.7 GB
      minRamBytes: 3 * 1024 * 1024 * 1024, // 3 GB
      recommendedRamBytes: 5 * 1024 * 1024 * 1024, // 5 GB
      contextSize: 2048,
      // Common Phi-2 GGUF location
      downloadUrl: 'https://huggingface.co/TheBloke/phi-2-GGUF/resolve/main/phi-2.Q4_K_M.gguf',
      sha256: '',
      supportedLanguages: ['en'],
      strengths: ['Good reasoning', 'Great for chat', 'Efficient'],
    ),
    
    // Llama 3.2 1B - Meta's small model
    ModelOption(
      id: 'llama3.2-1b-q4',
      name: 'Llama 3.2 1B',
      description: 'Meta\'s latest small model optimized for mobile. '
                   'Good balance of speed and quality.',
      parameters: '1B',
      quantization: 'Q4_K_M',
      sizeBytes: 750 * 1024 * 1024, // ~750 MB
      minRamBytes: 2 * 1024 * 1024 * 1024, // 2 GB
      recommendedRamBytes: 3 * 1024 * 1024 * 1024, // 3 GB
      contextSize: 8192,
      downloadUrl: 'https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf',
      sha256: '',
      supportedLanguages: ['en', 'de', 'fr', 'it', 'pt', 'hi', 'es', 'th'],
      strengths: ['Mobile optimized', 'Long context', 'Good quality'],
    ),
    
    // Llama 3.2 3B - Meta's mid-size mobile model
    ModelOption(
      id: 'llama3.2-3b-q4',
      name: 'Llama 3.2 3B',
      description: 'Meta\'s larger mobile model. Higher quality '
                   'for devices with more RAM.',
      parameters: '3B',
      quantization: 'Q4_K_M',
      sizeBytes: 2000 * 1024 * 1024, // ~2 GB
      minRamBytes: 4 * 1024 * 1024 * 1024, // 4 GB
      recommendedRamBytes: 6 * 1024 * 1024 * 1024, // 6 GB
      contextSize: 8192,
      downloadUrl: 'https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf',
      sha256: '',
      supportedLanguages: ['en', 'de', 'fr', 'it', 'pt', 'hi', 'es', 'th'],
      strengths: ['High quality', 'Mobile optimized', 'Long context'],
    ),
    
    // Mistral 7B - Premium option
    ModelOption(
      id: 'mistral-7b-q4',
      name: 'Mistral 7B v0.3',
      description: 'Premium quality model for high-end devices. '
                   'Best overall quality but requires powerful hardware.',
      parameters: '7B',
      quantization: 'Q4_K_M',
      sizeBytes: 4100 * 1024 * 1024, // ~4.1 GB
      minRamBytes: 6 * 1024 * 1024 * 1024, // 6 GB
      recommendedRamBytes: 8 * 1024 * 1024 * 1024, // 8 GB
      contextSize: 8192,
      downloadUrl: 'https://huggingface.co/bartowski/Mistral-7B-Instruct-v0.3-GGUF/resolve/main/Mistral-7B-Instruct-v0.3-Q4_K_M.gguf',
      sha256: '',
      supportedLanguages: ['en', 'fr', 'es', 'de', 'it', 'pt'],
      strengths: ['Highest quality', 'Best reasoning', 'Complex tasks'],
    ),
  ];
  
  /// Get models sorted by compatibility with device.
  static List<ModelOption> getModelsForDevice(DeviceSpecs specs) {
    return models.map((model) {
      final isRecommended = _isRecommendedForDevice(model, specs);
      return model.copyWithRecommended(isRecommended);
    }).toList();
  }
  
  /// Check if model is recommended for device.
  static bool _isRecommendedForDevice(ModelOption model, DeviceSpecs specs) {
    return specs.totalRamBytes >= model.recommendedRamBytes &&
           specs.availableStorageBytes >= model.sizeBytes * 1.2;
  }
  
  /// Get the best model for a device.
  static ModelOption? getBestModelForDevice(DeviceSpecs specs) {
    ModelOption? best;
    
    for (final model in models.reversed) {
      if (specs.totalRamBytes >= model.recommendedRamBytes &&
          specs.availableStorageBytes >= model.sizeBytes * 1.2) {
        best = model;
        break;
      }
    }
    
    if (best == null && specs.meetsMinimumRequirements) {
      best = models.first;
    }
    
    return best;
  }
  
  /// Find model by ID.
  static ModelOption? findById(String id) {
    try {
      return models.firstWhere((m) => m.id == id);
    } catch (_) {
      return null;
    }
  }
  
  /// Get models that can run on device.
  static List<ModelOption> getRunnableModels(DeviceSpecs specs) {
    return models.where((m) => specs.totalRamBytes >= m.minRamBytes).toList();
  }
}
