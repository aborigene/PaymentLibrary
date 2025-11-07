package com.dynatracese.paymentlibrary

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.WifiManager
import android.os.Build
import android.provider.Settings
import android.telephony.TelephonyManager
import android.util.Log
import androidx.core.content.ContextCompat
import java.net.InetAddress
import java.net.NetworkInterface
import java.util.Collections
import java.util.Locale
import java.util.TimeZone

/**
 * Collects comprehensive device and system metadata for business events
 */
object DeviceMetadataCollector {

    private const val TAG = "DeviceMetadataCollector" // Tag for logging

    // MARK: - Data Class

    data class DeviceMetadata(
        val osVersion: String,
        val osVersionCode: Int,
        val deviceModel: String,
        val deviceManufacturer: String,
        val deviceBrand: String,
        val deviceBoard: String,
        val deviceHardware: String,
        val ispName: String?,
        val networkType: String,
        val deviceIpAddress: String?,
        val androidId: String?,
        val screenDensity: String,
        val screenResolution: String,
        val availableMemory: String,
        val totalStorage: String,
        val locale: String,
        val timezone: String,
        val batteryLevel: String?
    )

    // MARK: - Public API

    /**
     * Collects all available device metadata
     * Note: Some information requires specific permissions. Missing permissions are logged.
     */
    fun collectMetadata(context: Context): DeviceMetadata {
        return DeviceMetadata(
            osVersion = getOSVersion(),
            osVersionCode = getOSVersionCode(),
            deviceModel = getDeviceModel(),
            deviceManufacturer = getDeviceManufacturer(),
            deviceBrand = getDeviceBrand(),
            deviceBoard = getDeviceBoard(),
            deviceHardware = getDeviceHardware(),
            ispName = getISPName(context),
            networkType = getNetworkType(context),
            deviceIpAddress = getDeviceIPAddress(),
            androidId = getAndroidId(context),
            screenDensity = getScreenDensity(context),
            screenResolution = getScreenResolution(context),
            availableMemory = getAvailableMemory(context),
            totalStorage = getTotalStorage(context),
            locale = getLocale(),
            timezone = getTimezone(),
            batteryLevel = getBatteryLevel(context)
        )
    }

    /**
     * Converts metadata to a formatted string for device.info field
     */
    fun formatDeviceInfo(metadata: DeviceMetadata): String {
        return buildString {
            append("${metadata.deviceManufacturer} ${metadata.deviceModel}")
            append(" (Android ${metadata.osVersion})")
            metadata.ispName?.let { append(" - ISP: $it") }
            metadata.deviceIpAddress?.let { append(" - IP: $it") }
        }
    }

    /**
     * Converts metadata to a map for inclusion in business event attributes
     */
    fun toEventAttributes(metadata: DeviceMetadata): Map<String, Any> {
        val attributes = mutableMapOf<String, Any>()

        // Device Hardware Information
        attributes["device.os.name"] = "Android"
        attributes["device.os.version"] = metadata.osVersion
        attributes["device.os.versionCode"] = metadata.osVersionCode
        attributes["device.manufacturer"] = metadata.deviceManufacturer
        attributes["device.model"] = metadata.deviceModel
        attributes["device.brand"] = metadata.deviceBrand
        attributes["device.board"] = metadata.deviceBoard
        attributes["device.hardware"] = metadata.deviceHardware

        // Network Information
        metadata.ispName?.let { attributes["network.isp"] = it }
        attributes["network.type"] = metadata.networkType
        metadata.deviceIpAddress?.let { attributes["network.ip"] = it }

        // Device Identifiers and Configuration
        metadata.androidId?.let { attributes["device.androidId"] = it }
        attributes["device.screen.density"] = metadata.screenDensity
        attributes["device.screen.resolution"] = metadata.screenResolution
        attributes["device.memory.available"] = metadata.availableMemory
        attributes["device.storage.total"] = metadata.totalStorage
        attributes["device.locale"] = metadata.locale
        attributes["device.timezone"] = metadata.timezone
        metadata.batteryLevel?.let { attributes["device.battery.level"] = it }

        return attributes.toMap()
    }

    // MARK: - Private Helper Methods

    private fun hasPermission(context: Context, permission: String): Boolean {
        return ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED
    }

    private fun logPermissionMissing(dataField: String, permission: String) {
        Log.w(TAG, "Data not collected: $dataField requires permission $permission, but it is not granted.")
    }

    private fun getOSVersion(): String = Build.VERSION.RELEASE

    private fun getOSVersionCode(): Int = Build.VERSION.SDK_INT

    private fun getDeviceModel(): String = Build.MODEL

    private fun getDeviceManufacturer(): String = Build.MANUFACTURER

    private fun getDeviceBrand(): String = Build.BRAND

    private fun getDeviceBoard(): String = Build.BOARD

    private fun getDeviceHardware(): String = Build.HARDWARE

    private fun getISPName(context: Context): String? {
        val permission = Manifest.permission.ACCESS_NETWORK_STATE
        if (!hasPermission(context, permission)) {
            // Log if the primary permission needed to check network type is missing
            logPermissionMissing("ISP Name (Base Network Check)", permission)
            return null
        }

        return try {
            val connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            val network = connectivityManager?.activeNetwork
            val networkCapabilities = connectivityManager?.getNetworkCapabilities(network)

            when {
                networkCapabilities?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true -> {
                    // getWifiISP will handle its own ACCESS_WIFI_STATE check
                    getWifiISP(context)
                }
                networkCapabilities?.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) == true -> {
                    // getCellularISP will handle its own READ_PHONE_STATE check
                    getCellularISP(context)
                }
                else -> null // No network, or transport type unknown
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error collecting ISP Name", e)
            null
        }
    }

    private fun getWifiISP(context: Context): String? {
        val permission = Manifest.permission.ACCESS_WIFI_STATE
        return try {
            if (hasPermission(context, permission)) {
                val wifiManager = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
                // Note: Getting SSID requires ACCESS_FINE_LOCATION or ACCESS_COARSE_LOCATION on some Android versions.
                // Assuming ACCESS_WIFI_STATE is the primary requirement for basic WiFi info.
                val wifiInfo = wifiManager?.connectionInfo
                wifiInfo?.ssid?.replace("\"", "")?.takeIf { it.isNotEmpty() } ?: "WiFi Network"
            } else {
                logPermissionMissing("WiFi ISP Name/SSID", permission)
                null
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error collecting WiFi ISP Name", e)
            null
        }
    }

    private fun getCellularISP(context: Context): String? {
        val permission = Manifest.permission.READ_PHONE_STATE
        return try {
            if (hasPermission(context, permission)) {
                val telephonyManager = context.getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
                telephonyManager?.networkOperatorName?.takeIf { it.isNotEmpty() } ?: "Cellular Network"
            } else {
                logPermissionMissing("Cellular ISP Name", permission)
                null
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error collecting Cellular ISP Name", e)
            null
        }
    }

    private fun getNetworkType(context: Context): String {
        return try {
            val connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            val network = connectivityManager?.activeNetwork
            val networkCapabilities = connectivityManager?.getNetworkCapabilities(network)

            when {
                networkCapabilities?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true -> "WiFi"
                networkCapabilities?.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) == true -> {
                    getCellularNetworkType(context)
                }
                networkCapabilities?.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) == true -> "Ethernet"
                networkCapabilities?.hasTransport(NetworkCapabilities.TRANSPORT_BLUETOOTH) == true -> "Bluetooth"
                else -> "Unknown"
            }
        } catch (e: Exception) {
            "Unknown"
        }
    }

    private fun getCellularNetworkType(context: Context): String {
        val permission = Manifest.permission.READ_PHONE_STATE
        return try {
            if (hasPermission(context, permission)) {
                val telephonyManager = context.getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
                // Requires permission.
                when (telephonyManager?.networkType) {
                    TelephonyManager.NETWORK_TYPE_LTE -> "4G LTE"
                    TelephonyManager.NETWORK_TYPE_NR -> "5G" // Added 5G
                    TelephonyManager.NETWORK_TYPE_HSPAP,
                    TelephonyManager.NETWORK_TYPE_HSPA,
                    TelephonyManager.NETWORK_TYPE_HSUPA,
                    TelephonyManager.NETWORK_TYPE_HSDPA,
                    TelephonyManager.NETWORK_TYPE_UMTS -> "3G"
                    TelephonyManager.NETWORK_TYPE_EDGE,
                    TelephonyManager.NETWORK_TYPE_GPRS,
                    TelephonyManager.NETWORK_TYPE_CDMA,
                    TelephonyManager.NETWORK_TYPE_1xRTT -> "2G"
                    else -> "Cellular"
                }
            } else {
                logPermissionMissing("Cellular Network Type (detail)", permission)
                // Fallback to "Cellular" if the general transport is cellular but detail is restricted.
                "Cellular"
            }
        } catch (e: Exception) {
            "Cellular"
        }
    }

    private fun getDeviceIPAddress(): String? {
        // No special permission is typically needed for getting the local IP through NetworkInterface,
        // but it might require INTERNET permission (which is usually granted).
        return try {
            val interfaces = Collections.list(NetworkInterface.getNetworkInterfaces())
            for (networkInterface in interfaces) {
                val addresses = Collections.list(networkInterface.inetAddresses)
                for (address in addresses) {
                    if (!address.isLoopbackAddress && address is InetAddress) {
                        val hostAddress = address.hostAddress
                        if (hostAddress != null && !hostAddress.contains(":")) {
                            // Return IPv4 address
                            return hostAddress
                        }
                    }
                }
            }
            null
        } catch (e: Exception) {
            Log.e(TAG, "Error collecting Device IP Address", e)
            null
        }
    }

    private fun getAndroidId(context: Context): String? {
        return try {
            // ANDROID_ID is usually accessible without special permissions, but can be restricted
            // on some specific devices or contexts.
            Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID)
        } catch (e: Exception) {
            Log.e(TAG, "Error collecting Android ID", e)
            null
        }
    }

    private fun getScreenDensity(context: Context): String {
        return try {
            val displayMetrics = context.resources.displayMetrics
            "${displayMetrics.densityDpi} dpi"
        } catch (e: Exception) {
            "Unknown"
        }
    }

    private fun getScreenResolution(context: Context): String {
        return try {
            val displayMetrics = context.resources.displayMetrics
            "${displayMetrics.widthPixels}x${displayMetrics.heightPixels}"
        } catch (e: Exception) {
            "Unknown"
        }
    }

    private fun getAvailableMemory(context: Context): String {
        return try {
            val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as? android.app.ActivityManager
            val memoryInfo = android.app.ActivityManager.MemoryInfo()
            activityManager?.getMemoryInfo(memoryInfo)
            val availableMB = memoryInfo.availMem / (1024 * 1024)
            "${availableMB}MB"
        } catch (e: Exception) {
            "Unknown"
        }
    }

    private fun getTotalStorage(context: Context): String {
        return try {
            // Use context.filesDir.absolutePath which is always available.
            val statFs = android.os.StatFs(context.filesDir.absolutePath)
            val totalBytes = statFs.totalBytes
            val totalGB = totalBytes / (1024 * 1024 * 1024)
            "${totalGB}GB"
        } catch (e: Exception) {
            "Unknown"
        }
    }

    private fun getLocale(): String {
        return try {
            Locale.getDefault().toString()
        } catch (e: Exception) {
            "Unknown"
        }
    }

    private fun getTimezone(): String {
        return try {
            TimeZone.getDefault().id
        } catch (e: Exception) {
            "Unknown"
        }
    }

    private fun getBatteryLevel(context: Context): String? {
        return try {
            val batteryManager = context.getSystemService(Context.BATTERY_SERVICE) as? android.os.BatteryManager
            // Requires no permission for basic level, but requires API 21+
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                val level = batteryManager?.getIntProperty(android.os.BatteryManager.BATTERY_PROPERTY_CAPACITY)
                if (level != null && level >= 0) "${level}%" else null
            } else {
                // Pre-Lollipop fallback (requires Intent registration, which is outside a simple getter)
                null
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error collecting Battery Level", e)
            null
        }
    }
}