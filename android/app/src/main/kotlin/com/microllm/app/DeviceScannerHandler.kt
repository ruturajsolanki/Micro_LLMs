package com.microllm.app

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.os.StatFs
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.RandomAccessFile

/**
 * Handler for scanning device hardware specifications.
 * 
 * Provides detailed information about:
 * - RAM (total and available)
 * - CPU (cores, architecture, frequency)
 * - Storage
 * - Device model and capabilities
 */
class DeviceScannerHandler(private val context: Context) {

    private val activityManager: ActivityManager by lazy {
        context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
    }

    fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "scanDevice" -> {
                val specs = scanDevice()
                result.success(specs)
            }
            
            "getMemoryStatus" -> {
                val status = getMemoryStatus()
                result.success(status)
            }
            
            "getCpuTemperature" -> {
                val temp = getCpuTemperature()
                if (temp != null) {
                    result.success(temp)
                } else {
                    result.error("UNAVAILABLE", "CPU temperature not available", null)
                }
            }
            
            "isThermalThrottling" -> {
                val throttling = isThermalThrottling()
                result.success(throttling)
            }
            
            else -> {
                result.notImplemented()
            }
        }
    }

    /**
     * Scan all device specifications.
     */
    private fun scanDevice(): Map<String, Any?> {
        val memInfo = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memInfo)

        val cpuInfo = getCpuInfo()
        val storageInfo = getStorageInfo()
        val socName = getSocName()

        return mapOf(
            // RAM
            "totalRamBytes" to memInfo.totalMem,
            "availableRamBytes" to memInfo.availMem,
            
            // CPU
            "cpuCores" to Runtime.getRuntime().availableProcessors(),
            "cpuArchitecture" to getCpuArchitecture(),
            "cpuMaxFrequencyMHz" to cpuInfo["maxFrequency"],
            "supportsNeon" to supportsNeon(),
            "hasNpu" to hasNpu(),
            
            // GPU
            "gpuName" to getGpuName(),
            
            // Storage
            "availableStorageBytes" to storageInfo["available"],
            "totalStorageBytes" to storageInfo["total"],
            
            // Device info
            "deviceModel" to "${Build.MANUFACTURER} ${Build.MODEL}",
            "sdkVersion" to Build.VERSION.SDK_INT,
            "socName" to socName,
            
            // Additional info
            "abis" to Build.SUPPORTED_ABIS.toList(),
            "is64Bit" to Build.SUPPORTED_64_BIT_ABIS.isNotEmpty()
        )
    }

    /**
     * Get current memory status.
     */
    private fun getMemoryStatus(): Map<String, Any> {
        val memInfo = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memInfo)

        return mapOf(
            "totalBytes" to memInfo.totalMem,
            "availableBytes" to memInfo.availMem,
            "usedBytes" to (memInfo.totalMem - memInfo.availMem),
            "lowMemoryThreshold" to memInfo.threshold,
            "isLowMemory" to memInfo.lowMemory
        )
    }

    /**
     * Get CPU information including frequency.
     */
    private fun getCpuInfo(): Map<String, Any?> {
        val maxFrequency = try {
            // Read max frequency from sysfs
            val file = File("/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq")
            if (file.exists()) {
                val freqKHz = file.readText().trim().toLongOrNull()
                freqKHz?.div(1000)?.toInt() // Convert kHz to MHz
            } else {
                null
            }
        } catch (e: Exception) {
            null
        }

        val currentFrequency = try {
            val file = File("/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq")
            if (file.exists()) {
                val freqKHz = file.readText().trim().toLongOrNull()
                freqKHz?.div(1000)?.toInt()
            } else {
                null
            }
        } catch (e: Exception) {
            null
        }

        return mapOf(
            "maxFrequency" to maxFrequency,
            "currentFrequency" to currentFrequency,
            "cores" to Runtime.getRuntime().availableProcessors()
        )
    }

    /**
     * Get CPU architecture string.
     */
    private fun getCpuArchitecture(): String {
        val abis = Build.SUPPORTED_ABIS
        return when {
            abis.contains("arm64-v8a") -> "arm64-v8a"
            abis.contains("armeabi-v7a") -> "armeabi-v7a"
            abis.contains("x86_64") -> "x86_64"
            abis.contains("x86") -> "x86"
            else -> abis.firstOrNull() ?: "unknown"
        }
    }

    /**
     * Check if CPU supports NEON SIMD instructions.
     */
    private fun supportsNeon(): Boolean {
        // NEON is mandatory for ARMv8 (arm64)
        if (Build.SUPPORTED_64_BIT_ABIS.contains("arm64-v8a")) {
            return true
        }
        
        // For 32-bit ARM, check cpuinfo
        return try {
            val cpuInfo = File("/proc/cpuinfo").readText()
            cpuInfo.contains("neon", ignoreCase = true) ||
            cpuInfo.contains("asimd", ignoreCase = true)
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Check if device has a Neural Processing Unit.
     */
    private fun hasNpu(): Boolean {
        // Check for known NPU indicators
        val socName = getSocName()?.lowercase() ?: ""
        
        return when {
            // Qualcomm Hexagon DSP (acts as NPU)
            socName.contains("snapdragon 8") -> true
            socName.contains("snapdragon 7") -> true
            
            // MediaTek APU
            socName.contains("dimensity") -> true
            
            // Samsung Exynos with NPU
            socName.contains("exynos 2") -> true
            socName.contains("exynos 1") -> true
            
            // Google Tensor
            socName.contains("tensor") -> true
            
            else -> false
        }
    }

    /**
     * Get SOC (System on Chip) name.
     */
    private fun getSocName(): String? {
        return try {
            // Try to get from Build
            val hardware = Build.HARDWARE
            val board = Build.BOARD
            
            // Try to read from cpuinfo
            val cpuInfo = File("/proc/cpuinfo").readText()
            val hardwareLine = cpuInfo.lines().find { 
                it.startsWith("Hardware", ignoreCase = true) 
            }
            
            hardwareLine?.substringAfter(":")?.trim()
                ?: if (hardware.isNotBlank()) hardware else board
        } catch (e: Exception) {
            Build.HARDWARE.takeIf { it.isNotBlank() }
        }
    }

    /**
     * Get GPU name if available.
     */
    private fun getGpuName(): String? {
        return try {
            // This is a simplified approach
            // In reality, you'd need OpenGL ES context to get renderer string
            val socName = getSocName()?.lowercase() ?: ""
            
            when {
                socName.contains("snapdragon") -> "Adreno"
                socName.contains("exynos") -> "Mali"
                socName.contains("dimensity") || socName.contains("helio") -> "Mali"
                socName.contains("tensor") -> "Mali"
                socName.contains("kirin") -> "Mali"
                else -> null
            }
        } catch (e: Exception) {
            null
        }
    }

    /**
     * Get storage information.
     */
    private fun getStorageInfo(): Map<String, Long> {
        return try {
            val dataDir = context.dataDir
            val stat = StatFs(dataDir.absolutePath)
            
            mapOf(
                "available" to stat.availableBytes,
                "total" to stat.totalBytes,
                "free" to stat.freeBytes
            )
        } catch (e: Exception) {
            mapOf(
                "available" to 0L,
                "total" to 0L,
                "free" to 0L
            )
        }
    }

    /**
     * Get CPU temperature (requires root on most devices).
     */
    private fun getCpuTemperature(): Double? {
        return try {
            // Try common thermal zone paths
            val thermalPaths = listOf(
                "/sys/class/thermal/thermal_zone0/temp",
                "/sys/devices/virtual/thermal/thermal_zone0/temp",
                "/sys/class/hwmon/hwmon0/temp1_input"
            )
            
            for (path in thermalPaths) {
                val file = File(path)
                if (file.exists() && file.canRead()) {
                    val temp = file.readText().trim().toDoubleOrNull()
                    if (temp != null) {
                        // Temperature is usually in millidegrees
                        return if (temp > 1000) temp / 1000.0 else temp
                    }
                }
            }
            null
        } catch (e: Exception) {
            null
        }
    }

    /**
     * Check if device is thermal throttling.
     */
    private fun isThermalThrottling(): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                // Use PowerManager thermal status on Android 10+
                val powerManager = context.getSystemService(Context.POWER_SERVICE) 
                    as android.os.PowerManager
                val thermalStatus = powerManager.currentThermalStatus
                thermalStatus >= android.os.PowerManager.THERMAL_STATUS_MODERATE
            } else {
                // Fallback: check if CPU frequency is below max
                val cpuInfo = getCpuInfo()
                val maxFreq = cpuInfo["maxFrequency"] as? Int
                val curFreq = cpuInfo["currentFrequency"] as? Int
                
                if (maxFreq != null && curFreq != null && maxFreq > 0) {
                    curFreq < maxFreq * 0.7 // If running below 70% of max
                } else {
                    false
                }
            }
        } catch (e: Exception) {
            false
        }
    }
}
