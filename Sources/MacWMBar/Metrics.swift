import Darwin
import Foundation
import IOKit.ps

/// System readings for the bar: CPU, network, battery and the clock.
enum SystemMetrics {
    static func currentTime() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date())
    }

    static func cpuTicks() -> [UInt32]? {
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &load) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        return withUnsafePointer(to: &load.cpu_ticks) { pointer in
            pointer.withMemoryRebound(to: UInt32.self, capacity: 4) {
                Array(UnsafeBufferPointer(start: $0, count: 4))
            }
        }
    }

    static func cpuUsage(current: [UInt32], previous: [UInt32]) -> String {
        guard current.count == previous.count, current.count > Int(CPU_STATE_IDLE) else { return "--" }
        let ticks = zip(current, previous).map { UInt64($0) >= UInt64($1) ? UInt64($0) - UInt64($1) : 0 }
        let total = ticks.reduce(UInt64(0)) { $0 + UInt64($1) }
        guard total > 0 else { return "--" }
        let idle = ticks[Int(CPU_STATE_IDLE)]
        return "\(Int((100 * (total - idle)) / total))%"
    }

    static func networkBytes() -> (input: UInt64, output: UInt64)? {
        var address: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&address) == 0 else { return nil }
        defer { freeifaddrs(address) }

        var input: UInt64 = 0
        var output: UInt64 = 0
        var current = address
        while let interface = current?.pointee {
            if interface.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
               let data = interface.ifa_data?.assumingMemoryBound(to: if_data.self).pointee {
                let name = String(cString: interface.ifa_name)
                if name != "lo0" {
                    input += UInt64(data.ifi_ibytes)
                    output += UInt64(data.ifi_obytes)
                }
            }
            current = interface.ifa_next
        }
        return input == 0 && output == 0 ? nil : (input, output)
    }

    static func rate(_ bytes: UInt64) -> String {
        let kilobytes = Double(bytes) / 1024
        if kilobytes < 1024 { return "\(Int(kilobytes))K/s" }
        return String(format: "%.1fM/s", kilobytes / 1024)
    }

    static func batteryStatus() -> String {
        let blob = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(blob).takeRetainedValue()
        let count = CFArrayGetCount(sources)
        guard count > 0 else { return "--" }
        for index in 0..<count {
            guard let source = CFArrayGetValueAtIndex(sources, index) else { continue }
            let powerSource = Unmanaged<CFTypeRef>.fromOpaque(source).takeUnretainedValue()
            guard let description = IOPSGetPowerSourceDescription(blob, powerSource)?.takeUnretainedValue()
                    as? [String: Any],
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int,
                  maximum > 0 else { continue }
            let fraction = Double(current) / Double(maximum)
            let percentage = Int((fraction * 100).rounded())
            let charging = (description[kIOPSIsChargingKey] as? Bool) == true
            return "\(percentage)%\(charging ? "+" : "")"
        }
        return "--"
    }
}
