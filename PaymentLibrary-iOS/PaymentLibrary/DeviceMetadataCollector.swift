//
//  DeviceMetadataCollector.swift
//  PaymentLibrary
//
//  Created by Enhanced Integration on 10/22/25.
//

import Foundation
import UIKit
import Network
import CoreTelephony
import SystemConfiguration
import os.log

/// Comprehensive device metadata collection for enhanced business events
public class DeviceMetadataCollector {
    
    /// Comprehensive device metadata structure
    public struct DeviceMetadata {
        // Device Information
        public let deviceManufacturer: String
        public let deviceModel: String
        public let deviceName: String
        public let deviceSystemName: String
        public let deviceSystemVersion: String
        public let deviceIdentifierForVendor: String?
        
        // Hardware Information  
        public let screenWidth: Double
        public let screenHeight: Double
        public let screenScale: Double
        public let screenBounds: String
        
        // System Information
        public let osVersion: String
        public let osVersionCode: String
        public let buildVersion: String
        public let kernelVersion: String
        
        // Memory and Storage
        public let memoryTotal: UInt64
        public let memoryAvailable: UInt64
        public let storageTotal: UInt64
        public let storageAvailable: UInt64
        
        // Network Information
        public let networkType: String
        public let carrierName: String?
        public let carrierCountryCode: String?
        public let ispName: String?
        public let deviceIpAddress: String?
        
        // Application Context
        public let deviceLocale: String
        public let deviceTimezone: String
        public let batteryLevel: Float
        public let batteryState: String
        public let isLowPowerModeEnabled: Bool
        
        // Performance Information
        public let processorCount: Int
        public let thermalState: String
        
        public init(
            deviceManufacturer: String,
            deviceModel: String,
            deviceName: String,
            deviceSystemName: String,
            deviceSystemVersion: String,
            deviceIdentifierForVendor: String?,
            screenWidth: Double,
            screenHeight: Double,
            screenScale: Double,
            screenBounds: String,
            osVersion: String,
            osVersionCode: String,
            buildVersion: String,
            kernelVersion: String,
            memoryTotal: UInt64,
            memoryAvailable: UInt64,
            storageTotal: UInt64,
            storageAvailable: UInt64,
            networkType: String,
            carrierName: String?,
            carrierCountryCode: String?,
            ispName: String?,
            deviceIpAddress: String?,
            deviceLocale: String,
            deviceTimezone: String,
            batteryLevel: Float,
            batteryState: String,
            isLowPowerModeEnabled: Bool,
            processorCount: Int,
            thermalState: String
        ) {
            self.deviceManufacturer = deviceManufacturer
            self.deviceModel = deviceModel
            self.deviceName = deviceName
            self.deviceSystemName = deviceSystemName
            self.deviceSystemVersion = deviceSystemVersion
            self.deviceIdentifierForVendor = deviceIdentifierForVendor
            self.screenWidth = screenWidth
            self.screenHeight = screenHeight
            self.screenScale = screenScale
            self.screenBounds = screenBounds
            self.osVersion = osVersion
            self.osVersionCode = osVersionCode
            self.buildVersion = buildVersion
            self.kernelVersion = kernelVersion
            self.memoryTotal = memoryTotal
            self.memoryAvailable = memoryAvailable
            self.storageTotal = storageTotal
            self.storageAvailable = storageAvailable
            self.networkType = networkType
            self.carrierName = carrierName
            self.carrierCountryCode = carrierCountryCode
            self.ispName = ispName
            self.deviceIpAddress = deviceIpAddress
            self.deviceLocale = deviceLocale
            self.deviceTimezone = deviceTimezone
            self.batteryLevel = batteryLevel
            self.batteryState = batteryState
            self.isLowPowerModeEnabled = isLowPowerModeEnabled
            self.processorCount = processorCount
            self.thermalState = thermalState
        }
    }
    
    /// Collect comprehensive device metadata
    /// - Returns: Complete device metadata structure
    public static func collectMetadata() -> DeviceMetadata {
        let device = UIDevice.current
        let screen = UIScreen.main
        let locale = Locale.current
        let timezone = TimeZone.current
        let processInfo = ProcessInfo.processInfo
        
        return DeviceMetadata(
            deviceManufacturer: "Apple",
            deviceModel: getDeviceModel(),
            deviceName: device.name,
            deviceSystemName: device.systemName,
            deviceSystemVersion: device.systemVersion,
            deviceIdentifierForVendor: device.identifierForVendor?.uuidString,
            screenWidth: Double(screen.bounds.width * screen.scale),
            screenHeight: Double(screen.bounds.height * screen.scale),
            screenScale: Double(screen.scale),
            screenBounds: "\(Int(screen.bounds.width))x\(Int(screen.bounds.height))",
            osVersion: "\(device.systemName) \(device.systemVersion)",
            osVersionCode: device.systemVersion,
            buildVersion: getBuildVersion(),
            kernelVersion: getKernelVersion(),
            memoryTotal: getMemoryTotal(),
            memoryAvailable: getMemoryAvailable(),
            storageTotal: getStorageTotal(),
            storageAvailable: getStorageAvailable(),
            networkType: getNetworkType(),
            carrierName: getCarrierName(),
            carrierCountryCode: getCarrierCountryCode(),
            ispName: getISPName(),
            deviceIpAddress: getDeviceIPAddress(),
            deviceLocale: locale.identifier,
            deviceTimezone: timezone.identifier,
            batteryLevel: getBatteryLevel(),
            batteryState: getBatteryState(),
            isLowPowerModeEnabled: processInfo.isLowPowerModeEnabled,
            processorCount: processInfo.processorCount,
            thermalState: getThermalState()
        )
    }
    
    /// Format device metadata into a human-readable string
    /// - Parameter metadata: Device metadata to format
    /// - Returns: Formatted device information string
    public static func formatDeviceInfo(_ metadata: DeviceMetadata) -> String {
        return "\(metadata.deviceModel) (\(metadata.osVersion)) - \(metadata.screenBounds) - \(metadata.networkType)"
    }
    
    /// Collect only dynamic metadata that changes frequently (optimized for real-time collection)
    /// - Returns: Dynamic device metadata dictionary
    public static func collectDynamicMetadata() -> [String: Any] {
        let device = UIDevice.current
        let processInfo = ProcessInfo.processInfo
        
        return [
            // Dynamic system information
            "device.battery_level": getBatteryLevel(),
            "device.battery_state": getBatteryState(),
            "device.memory_available": getMemoryAvailable(),
            "device.storage_available": getStorageAvailable(),
            "device.thermal_state": getThermalState(),
            "device.low_power_mode": processInfo.isLowPowerModeEnabled,
            
            // Dynamic network information  
            "network.type": getNetworkType(),
            "device.ip_address": getDeviceIPAddress() ?? "unknown",
            
            // Collection timestamp
            "metadata.collection_time": ISO8601DateFormatter().string(from: Date()),
            "metadata.collection_type": "dynamic"
        ]
    }
    
    /// Collect complete static metadata (device model, OS version, etc.)
    /// - Returns: Static device metadata dictionary  
    public static func collectStaticMetadata() -> [String: Any] {
        let metadata = collectMetadata()
        return [
            // Device Information
            "device.manufacturer": metadata.deviceManufacturer,
            "device.model": metadata.deviceModel,
            "device.name": metadata.deviceName,
            "device.system_name": metadata.deviceSystemName,
            "device.identifier": metadata.deviceIdentifierForVendor ?? "unknown",
            
            // Operating System
            "device.os_version": metadata.osVersion,
            "device.os_version_code": metadata.osVersionCode,
            "device.build_version": metadata.buildVersion,
            "device.kernel_version": metadata.kernelVersion,
            
            // Screen Information  
            "device.screen_width": metadata.screenWidth,
            "device.screen_height": metadata.screenHeight,
            "device.screen_scale": metadata.screenScale,
            "device.screen_bounds": metadata.screenBounds,
            
            // Hardware Specifications
            "device.memory_total": metadata.memoryTotal,
            "device.storage_total": metadata.storageTotal,
            "device.processor_count": metadata.processorCount,
            
            // Network Capabilities
            "network.carrier": metadata.carrierName ?? "unknown",
            "network.country_code": metadata.carrierCountryCode ?? "unknown",
            
            // System Context
            "device.locale": metadata.deviceLocale,
            "device.timezone": metadata.deviceTimezone,
            
            // Collection info
            "metadata.collection_time": ISO8601DateFormatter().string(from: Date()),
            "metadata.collection_type": "static"
        ]
    }
    
    /// Convert device metadata to event attributes dictionary
    /// - Parameter metadata: Device metadata to convert
    /// - Returns: Dictionary suitable for business event attributes
    public static func toEventAttributes(_ metadata: DeviceMetadata) -> [String: Any] {
        return [
            // Device Information
            "device.manufacturer": metadata.deviceManufacturer,
            "device.model": metadata.deviceModel,
            "device.name": metadata.deviceName,
            "device.system_name": metadata.deviceSystemName,
            "device.identifier": metadata.deviceIdentifierForVendor ?? "unknown",
            
            // Operating System (aligned with Android field names)
            "device.os.family": "iOS",
            "device.os.name": metadata.deviceSystemName, // "iOS", "iPadOS", "tvOS", etc.
            "device.os.version": metadata.osVersion,
            "device.os.versionCode": metadata.osVersionCode,
            "device.build_version": metadata.buildVersion,
            "device.kernel_version": metadata.kernelVersion,
            
            // Screen Information
            "device.screen_width": metadata.screenWidth,
            "device.screen_height": metadata.screenHeight,
            "device.screen_scale": metadata.screenScale,
            "device.screen_bounds": metadata.screenBounds,
            
            // Memory and Storage
            "device.memory_total": metadata.memoryTotal,
            "device.memory_available": metadata.memoryAvailable,
            "device.storage_total": metadata.storageTotal,
            "device.storage_available": metadata.storageAvailable,
            
            // Network Information
            "network.type": metadata.networkType,
            "network.carrier": metadata.carrierName ?? "unknown",
            "network.country_code": metadata.carrierCountryCode ?? "unknown",
            "network.isp": metadata.ispName ?? "unknown",
            "network.ip_address": metadata.deviceIpAddress ?? "unknown",
            
            // System Context
            "device.locale": metadata.deviceLocale,
            "device.timezone": metadata.deviceTimezone,
            "device.battery_level": metadata.batteryLevel,
            "device.battery_state": metadata.batteryState,
            "device.low_power_mode": metadata.isLowPowerModeEnabled,
            
            // Performance
            "device.processor_count": metadata.processorCount,
            "device.thermal_state": metadata.thermalState
        ]
    }
    
    // MARK: - Private Helper Methods
    
    private static func getDeviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            let unicodeScalar = UnicodeScalar(UInt8(value))
            return identifier + String(unicodeScalar)
        }
        return mapToDevice(identifier: identifier)
    }
    
    private static func mapToDevice(identifier: String) -> String {
        switch identifier {
        case "iPod5,1": return "iPod Touch 5"
        case "iPod7,1": return "iPod Touch 6"
        case "iPod9,1": return "iPod Touch 7"
        case "iPhone3,1", "iPhone3,2", "iPhone3,3": return "iPhone 4"
        case "iPhone4,1": return "iPhone 4s"
        case "iPhone5,1", "iPhone5,2": return "iPhone 5"
        case "iPhone5,3", "iPhone5,4": return "iPhone 5c"
        case "iPhone6,1", "iPhone6,2": return "iPhone 5s"
        case "iPhone7,2": return "iPhone 6"
        case "iPhone7,1": return "iPhone 6 Plus"
        case "iPhone8,1": return "iPhone 6s"
        case "iPhone8,2": return "iPhone 6s Plus"
        case "iPhone9,1", "iPhone9,3": return "iPhone 7"
        case "iPhone9,2", "iPhone9,4": return "iPhone 7 Plus"
        case "iPhone8,4": return "iPhone SE"
        case "iPhone10,1", "iPhone10,4": return "iPhone 8"
        case "iPhone10,2", "iPhone10,5": return "iPhone 8 Plus"
        case "iPhone10,3", "iPhone10,6": return "iPhone X"
        case "iPhone11,2": return "iPhone XS"
        case "iPhone11,4", "iPhone11,6": return "iPhone XS Max"
        case "iPhone11,8": return "iPhone XR"
        case "iPhone12,1": return "iPhone 11"
        case "iPhone12,3": return "iPhone 11 Pro"
        case "iPhone12,5": return "iPhone 11 Pro Max"
        case "iPhone12,8": return "iPhone SE (2nd generation)"
        case "iPhone13,1": return "iPhone 12 mini"
        case "iPhone13,2": return "iPhone 12"
        case "iPhone13,3": return "iPhone 12 Pro"
        case "iPhone13,4": return "iPhone 12 Pro Max"
        case "iPhone14,4": return "iPhone 13 mini"
        case "iPhone14,5": return "iPhone 13"
        case "iPhone14,2": return "iPhone 13 Pro"
        case "iPhone14,3": return "iPhone 13 Pro Max"
        case "iPhone14,6": return "iPhone SE (3rd generation)"
        case "iPhone14,7": return "iPhone 14"
        case "iPhone14,8": return "iPhone 14 Plus"
        case "iPhone15,2": return "iPhone 14 Pro"
        case "iPhone15,3": return "iPhone 14 Pro Max"
        case "iPhone15,4": return "iPhone 15"
        case "iPhone15,5": return "iPhone 15 Plus"
        case "iPhone16,1": return "iPhone 15 Pro"
        case "iPhone16,2": return "iPhone 15 Pro Max"
        case "iPad2,1", "iPad2,2", "iPad2,3", "iPad2,4": return "iPad 2"
        case "iPad3,1", "iPad3,2", "iPad3,3": return "iPad 3"
        case "iPad3,4", "iPad3,5", "iPad3,6": return "iPad 4"
        case "iPad4,1", "iPad4,2", "iPad4,3": return "iPad Air"
        case "iPad5,3", "iPad5,4": return "iPad Air 2"
        case "iPad6,11", "iPad6,12": return "iPad 5"
        case "iPad7,5", "iPad7,6": return "iPad 6"
        case "iPad11,3", "iPad11,4": return "iPad Air 3"
        case "iPad13,1", "iPad13,2": return "iPad Air 4"
        case "iPad13,16", "iPad13,17": return "iPad Air 5"
        case "iPad2,5", "iPad2,6", "iPad2,7": return "iPad Mini"
        case "iPad4,4", "iPad4,5", "iPad4,6": return "iPad Mini 2"
        case "iPad4,7", "iPad4,8", "iPad4,9": return "iPad Mini 3"
        case "iPad5,1", "iPad5,2": return "iPad Mini 4"
        case "iPad11,1", "iPad11,2": return "iPad Mini 5"
        case "iPad14,1", "iPad14,2": return "iPad Mini 6"
        case "iPad6,3", "iPad6,4": return "iPad Pro 9.7 Inch"
        case "iPad6,7", "iPad6,8": return "iPad Pro 12.9 Inch"
        case "iPad7,1", "iPad7,2": return "iPad Pro 12.9 Inch 2"
        case "iPad7,3", "iPad7,4": return "iPad Pro 10.5 Inch"
        case "iPad8,1", "iPad8,2", "iPad8,3", "iPad8,4": return "iPad Pro 11 Inch"
        case "iPad8,5", "iPad8,6", "iPad8,7", "iPad8,8": return "iPad Pro 12.9 Inch 3"
        case "iPad8,9", "iPad8,10": return "iPad Pro 11 Inch 2"
        case "iPad8,11", "iPad8,12": return "iPad Pro 12.9 Inch 4"
        case "iPad13,4", "iPad13,5", "iPad13,6", "iPad13,7": return "iPad Pro 11 Inch 3"
        case "iPad13,8", "iPad13,9", "iPad13,10", "iPad13,11": return "iPad Pro 12.9 Inch 5"
        case "AppleTV5,3": return "Apple TV"
        case "AppleTV6,2": return "Apple TV 4K"
        case "AudioAccessory1,1": return "HomePod"
        case "i386", "x86_64", "arm64": return "Simulator \(mapToDevice(identifier: ProcessInfo().environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "iOS"))"
        default: return identifier
        }
    }
    
    private static func getBuildVersion() -> String {
        guard let buildVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String else {
            return "unknown"
        }
        return buildVersion
    }
    
    private static func getKernelVersion() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let versionString = withUnsafePointer(to: &systemInfo.version) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0)
            }
        }
        return versionString ?? "unknown"
    }
    
    private static func getMemoryTotal() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return UInt64(ProcessInfo.processInfo.physicalMemory)
        } else {
            return 0
        }
    }
    
    private static func getMemoryAvailable() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return UInt64(info.resident_size)
        } else {
            return 0
        }
    }
    
    private static func getStorageTotal() -> UInt64 {
        do {
            let systemAttributes = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
            return (systemAttributes[.systemSize] as? NSNumber)?.uint64Value ?? 0
        } catch {
            return 0
        }
    }
    
    private static func getStorageAvailable() -> UInt64 {
        do {
            let systemAttributes = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
            return (systemAttributes[.systemFreeSize] as? NSNumber)?.uint64Value ?? 0
        } catch {
            return 0
        }
    }
    
    private static func getNetworkType() -> String {
        var zeroAddress = sockaddr_in(sin_len: 0, sin_family: 0, sin_port: 0, sin_addr: in_addr(s_addr: 0), sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))
        zeroAddress.sin_len = UInt8(MemoryLayout.size(ofValue: zeroAddress))
        zeroAddress.sin_family = sa_family_t(AF_INET)
        
        let defaultRouteReachability = withUnsafePointer(to: &zeroAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { zeroSockAddress in
                SCNetworkReachabilityCreateWithAddress(nil, zeroSockAddress)
            }
        }
        
        guard let reachability = defaultRouteReachability else {
            return "unknown"
        }
        
        var flags: SCNetworkReachabilityFlags = SCNetworkReachabilityFlags(rawValue: 0)
        if SCNetworkReachabilityGetFlags(reachability, &flags) == false {
            return "unknown"
        }
        
        if flags.contains(.reachable) && !flags.contains(.connectionRequired) {
            if flags.contains(.isWWAN) {
                return "cellular"
            } else {
                return "wifi"
            }
        }
        
        return "none"
    }
    
    private static func getCarrierName() -> String? {
        if #available(iOS 12.0, *) {
            let networkInfo = CTTelephonyNetworkInfo()
            if let carriers = networkInfo.serviceSubscriberCellularProviders {
                return carriers.values.first?.carrierName
            }
        } else {
            let networkInfo = CTTelephonyNetworkInfo()
            return networkInfo.subscriberCellularProvider?.carrierName
        }
        return nil
    }
    
    private static func getCarrierCountryCode() -> String? {
        if #available(iOS 12.0, *) {
            let networkInfo = CTTelephonyNetworkInfo()
            if let carriers = networkInfo.serviceSubscriberCellularProviders {
                return carriers.values.first?.isoCountryCode
            }
        } else {
            let networkInfo = CTTelephonyNetworkInfo()
            return networkInfo.subscriberCellularProvider?.isoCountryCode
        }
        return nil
    }
    
    private static func getISPName() -> String? {
        // Note: ISP name detection on iOS is limited due to privacy restrictions
        // This is a placeholder - actual ISP detection would require additional frameworks
        return "unknown"
    }
    
    private static func getDeviceIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while ptr != nil {
                defer { ptr = ptr?.pointee.ifa_next }
                
                let interface = ptr?.pointee
                let addrFamily = interface?.ifa_addr.pointee.sa_family
                if addrFamily == UInt8(AF_INET) || addrFamily == UInt8(AF_INET6) {
                    
                    let name = String(cString: (interface?.ifa_name)!)
                    if name == "en0" || name == "pdp_ip0" {
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        getnameinfo(interface?.ifa_addr, socklen_t((interface?.ifa_addr.pointee.sa_len)!), &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST)
                        address = String(cString: hostname)
                    }
                }
            }
            freeifaddrs(ifaddr)
        }
        
        return address
    }
    
    private static func getBatteryLevel() -> Float {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        return device.batteryLevel
    }
    
    private static func getBatteryState() -> String {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        
        switch device.batteryState {
        case .unplugged:
            return "unplugged"
        case .charging:
            return "charging"
        case .full:
            return "full"
        case .unknown:
            return "unknown"
        @unknown default:
            return "unknown"
        }
    }
    
    private static func getThermalState() -> String {
        let processInfo = ProcessInfo.processInfo
        
        switch processInfo.thermalState {
        case .nominal:
            return "nominal"
        case .fair:
            return "fair"
        case .serious:
            return "serious"
        case .critical:
            return "critical"
        @unknown default:
            return "unknown"
        }
    }
}