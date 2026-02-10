package com.microllm.app

import android.app.ActivityManager
import android.content.Context
import android.os.Debug
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Handler for memory monitoring operations.
 * 
 * Provides information about device memory status for OOM prevention.
 */
class MemoryHandler(private val context: Context) {

    private val activityManager: ActivityManager by lazy {
        context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
    }

    fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getMemoryInfo" -> {
                val memInfo = getMemoryInfo()
                result.success(memInfo)
            }
            
            "getAppMemoryUsage" -> {
                val appMemory = getAppMemoryUsage()
                result.success(appMemory)
            }
            
            "isLowMemory" -> {
                val isLow = isLowMemory()
                result.success(isLow)
            }
            
            "getAvailableStorage" -> {
                val storage = getAvailableStorage()
                result.success(storage)
            }
            
            "cleanupRam" -> {
                val cleanupResult = performRamCleanup()
                result.success(cleanupResult)
            }
            
            "getMemoryClass" -> {
                result.success(getMemoryClass())
            }
            
            "getLargeMemoryClass" -> {
                result.success(getLargeMemoryClass())
            }
            
            else -> {
                result.notImplemented()
            }
        }
    }

    /**
     * Get system memory information.
     */
    private fun getMemoryInfo(): Map<String, Long> {
        val memInfo = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memInfo)

        return mapOf(
            "totalBytes" to memInfo.totalMem,
            "availableBytes" to memInfo.availMem,
            "thresholdBytes" to memInfo.threshold,
            "lowMemory" to if (memInfo.lowMemory) 1L else 0L
        )
    }

    /**
     * Get memory used by this app.
     */
    private fun getAppMemoryUsage(): Map<String, Long> {
        val runtime = Runtime.getRuntime()
        val nativeHeap = Debug.getNativeHeapAllocatedSize()
        
        // Get process memory info
        val pids = intArrayOf(android.os.Process.myPid())
        val memoryInfo = activityManager.getProcessMemoryInfo(pids)
        
        val dalvikPss = memoryInfo.firstOrNull()?.dalvikPss?.toLong() ?: 0L
        val nativePss = memoryInfo.firstOrNull()?.nativePss?.toLong() ?: 0L
        val otherPss = memoryInfo.firstOrNull()?.otherPss?.toLong() ?: 0L
        
        return mapOf(
            "javaHeapUsed" to (runtime.totalMemory() - runtime.freeMemory()),
            "javaHeapMax" to runtime.maxMemory(),
            "nativeHeapUsed" to nativeHeap,
            "dalvikPss" to dalvikPss * 1024, // Convert KB to bytes
            "nativePss" to nativePss * 1024,
            "otherPss" to otherPss * 1024,
            "totalPss" to (dalvikPss + nativePss + otherPss) * 1024
        )
    }

    /**
     * Check if system is in low memory state.
     */
    private fun isLowMemory(): Boolean {
        val memInfo = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memInfo)
        return memInfo.lowMemory
    }

    /**
     * Get available storage in app's data directory.
     */
    private fun getAvailableStorage(): Long {
        return try {
            val dataDir = context.dataDir
            val stat = android.os.StatFs(dataDir.absolutePath)
            stat.availableBytes
        } catch (e: Exception) {
            -1L
        }
    }

    /**
     * Request garbage collection (use sparingly).
     */
    fun suggestGC() {
        Runtime.getRuntime().gc()
    }

    /**
     * Perform comprehensive RAM cleanup and return stats.
     * 
     * This method:
     * 1. Records memory before cleanup
     * 2. Triggers garbage collection multiple times
     * 3. Clears any caches we control
     * 4. Returns memory freed
     */
    private fun performRamCleanup(): Map<String, Any> {
        // Record memory before cleanup
        val memInfoBefore = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memInfoBefore)
        val availableBefore = memInfoBefore.availMem
        
        val runtime = Runtime.getRuntime()
        val javaHeapBefore = runtime.totalMemory() - runtime.freeMemory()
        val nativeHeapBefore = Debug.getNativeHeapAllocatedSize()
        
        // Perform multiple GC passes for thorough cleanup
        repeat(3) {
            runtime.gc()
            System.runFinalization()
            runtime.gc()
            // Small delay between passes
            Thread.sleep(50)
        }
        
        // Trim memory if possible (hint to system)
        try {
            if (context is android.content.ComponentCallbacks2) {
                (context as android.content.ComponentCallbacks2).onTrimMemory(
                    android.content.ComponentCallbacks2.TRIM_MEMORY_UI_HIDDEN
                )
            }
        } catch (e: Exception) {
            // Ignore if not supported
        }
        
        // Record memory after cleanup
        val memInfoAfter = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memInfoAfter)
        val availableAfter = memInfoAfter.availMem
        
        val javaHeapAfter = runtime.totalMemory() - runtime.freeMemory()
        val nativeHeapAfter = Debug.getNativeHeapAllocatedSize()
        
        // Calculate freed memory
        val systemFreed = availableAfter - availableBefore
        val javaHeapFreed = javaHeapBefore - javaHeapAfter
        val nativeHeapFreed = nativeHeapBefore - nativeHeapAfter
        
        return mapOf(
            "success" to true,
            "systemAvailableBefore" to availableBefore,
            "systemAvailableAfter" to availableAfter,
            "systemFreedBytes" to maxOf(0L, systemFreed),
            "javaHeapFreedBytes" to maxOf(0L, javaHeapFreed),
            "nativeHeapFreedBytes" to maxOf(0L, nativeHeapFreed),
            "totalFreedBytes" to maxOf(0L, javaHeapFreed + nativeHeapFreed),
            "isLowMemory" to memInfoAfter.lowMemory
        )
    }

    /**
     * Get memory class (max heap size in MB for this device).
     */
    fun getMemoryClass(): Int {
        return activityManager.memoryClass
    }

    /**
     * Get large memory class (if manifest requests largeHeap).
     */
    fun getLargeMemoryClass(): Int {
        return activityManager.largeMemoryClass
    }
}
