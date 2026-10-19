import Foundation
import IOKit.ps
import Darwin

/// Samples CPU, memory, battery, disk and network every two seconds.
final class SystemMonitor: ObservableObject {
    static let shared = SystemMonitor()

    @Published var cpu: Double = 0
    @Published var cpuUser: Double = 0
    @Published var cpuSystem: Double = 0
    @Published var memory: Double = 0
    @Published var memoryUsed: Double = 0
    @Published var memoryTotal: Double = Double(ProcessInfo.processInfo.physicalMemory)
    @Published var battery: Double = 0
    @Published var hasBattery = false
    @Published var charging = false
    @Published var onAC = true
    @Published var batteryMinutes: Int?
    @Published var diskUsed: Double = 0
    @Published var diskFree: Double = 0
    @Published var diskTotal: Double = 0
    @Published var down: Double = 0
    @Published var up: Double = 0

    private var timer: Timer?
    private var prevTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?
    private var prevNet: (rx: UInt64, tx: UInt64, time: Date)?
    private var tick = 0

    func start() {
        guard timer == nil else { return }
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.sample() }
    }

    private func sample() {
        sampleCPU()
        sampleMemory()
        sampleNetwork()
        if tick % 5 == 0 { sampleBattery(); sampleDisk() }
        tick += 1
    }

    private func sampleCPU() {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard r == KERN_SUCCESS else { return }
        let t = (user: UInt64(info.cpu_ticks.0), system: UInt64(info.cpu_ticks.1), idle: UInt64(info.cpu_ticks.2), nice: UInt64(info.cpu_ticks.3))
        if let p = prevTicks {
            let user = Double(t.user &- p.user + t.nice &- p.nice)
            let sys = Double(t.system &- p.system)
            let idle = Double(t.idle &- p.idle)
            let total = user + sys + idle
            if total > 0 {
                cpuUser = user / total
                cpuSystem = sys / total
                cpu = (user + sys) / total
            }
        }
        prevTicks = t
    }

    private func sampleMemory() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let r = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard r == KERN_SUCCESS else { return }
        let page = Double(vm_kernel_page_size)
        // Matches Activity Monitor's "Memory Used": app memory + wired + compressed.
        let app = Double(stats.internal_page_count) - Double(stats.purgeable_count)
        let used = (app + Double(stats.wire_count) + Double(stats.compressor_page_count)) * page
        memoryUsed = used
        memory = min(1, used / memoryTotal)
    }

    private func sampleBattery() {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return }
        hasBattery = false
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            hasBattery = true
            let cur = d[kIOPSCurrentCapacityKey] as? Double ?? 0
            let max = d[kIOPSMaxCapacityKey] as? Double ?? 100
            battery = max > 0 ? cur / max : 0
            charging = d[kIOPSIsChargingKey] as? Bool ?? false
            onAC = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let mins = (charging ? d[kIOPSTimeToFullChargeKey] : d[kIOPSTimeToEmptyKey]) as? Int ?? -1
            batteryMinutes = mins > 0 ? mins : nil
        }
    }

    private func sampleDisk() {
        let url = URL(fileURLWithPath: "/")
        guard let v = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
              let total = v.volumeTotalCapacity, let free = v.volumeAvailableCapacityForImportantUsage else { return }
        diskTotal = Double(total)
        diskFree = Double(free)
        diskUsed = total > 0 ? 1 - Double(free) / Double(total) : 0
    }

    private func sampleNetwork() {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return }
        defer { freeifaddrs(ifaddr) }
        var rx: UInt64 = 0, tx: UInt64 = 0
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            let ifa = p.pointee
            if let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK), let data = ifa.ifa_data {
                let name = String(cString: ifa.ifa_name)
                if !name.hasPrefix("lo") && !name.hasPrefix("utun") && !name.hasPrefix("awdl") && !name.hasPrefix("llw") {
                    let d = data.assumingMemoryBound(to: if_data.self).pointee
                    rx += UInt64(d.ifi_ibytes)
                    tx += UInt64(d.ifi_obytes)
                }
            }
            ptr = ifa.ifa_next
        }
        let now = Date()
        if let p = prevNet {
            let dt = now.timeIntervalSince(p.time)
            if dt > 0 {
                // Counters are 32-bit and wrap; ignore a negative delta.
                down = rx >= p.rx ? Double(rx - p.rx) / dt : 0
                up = tx >= p.tx ? Double(tx - p.tx) / dt : 0
            }
        }
        prevNet = (rx, tx, now)
    }
}
