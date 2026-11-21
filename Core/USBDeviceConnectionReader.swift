import CoreFoundation
import Foundation
import IOKit

/// Connection evidence only. Enumeration says nothing about measured power,
/// and a power-only accessory may not enumerate as a USB device at all.
enum USBDeviceConnectionReader {
    static func hasExternalDevice() -> Bool {
        guard let matching = IOServiceMatching("IOUSBHostDevice") else { return false }
        var iterator: io_iterator_t = IO_OBJECT_NULL
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        defer {
            if iterator != IO_OBJECT_NULL { IOObjectRelease(iterator) }
        }
        guard result == KERN_SUCCESS else { return false }

        for _ in 0..<128 {
            let service = IOIteratorNext(iterator)
            guard service != IO_OBJECT_NULL else { return false }
            defer { IOObjectRelease(service) }
            let portType = IORegistryEntryCreateCFProperty(
                service, "USBPortType" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue()
            if isExternalPortType(portType) { return true }
        }
        return false
    }

    static func isExternalPortType(_ raw: Any?) -> Bool {
        guard let number = raw as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return false }
        // IOUSBHostFamily defines 0 as standard and 5 as USB-C. This registry
        // property may change; missing/unknown types provide no connection hint.
        // Captive/internal ports are deliberately excluded.
        // Compare the value itself: integer conversion would accept fractions.
        return number.doubleValue == 0 || number.doubleValue == 5
    }
}
