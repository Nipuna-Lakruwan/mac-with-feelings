import AppKit
import Darwin
import FeelingsCore
import IOKit.ps

/// Reads the Mac's body: CPU, heat, battery, memory, disk, apps and how long the human has been at it.
@MainActor
final class VitalsSampler {
    private var lastTicks: (busy: UInt64, total: UInt64)?
    private var cpuHistory: [Double] = []
    private var workStart = Date()
    private var frontApp: String?
    private var frontSince = Date()
    private let tabs = TabCounter()
    private var lastTabCheck = Date.distantPast
    private var cachedTabs: Int?

    /// Stepping away for this long counts as a break.
    static let breakSeconds: Double = 5 * 60

    func sample(countTabs: Bool) -> Vitals {
        let now = Date()
        let idle = Self.idleSeconds()
        if idle >= Self.breakSeconds { workStart = now }

        let front = NSWorkspace.shared.frontmostApplication?.localizedName
        if front != frontApp {
            frontApp = front
            frontSince = now
        }

        // AppleScript is slow and asks for permission once, so ask browsers every 30 s at most.
        if countTabs {
            if now.timeIntervalSince(lastTabCheck) >= 30 {
                cachedTabs = tabs.count()
                lastTabCheck = now
            }
        } else {
            cachedTabs = nil
        }

        let (memPercent, pressure) = Self.memory()
        return Vitals(
            cpuPercent: smoothedCPU(),
            thermal: Self.thermal(),
            battery: Self.battery(),
            memoryUsedPercent: memPercent,
            memoryPressure: pressure,
            swapUsedGB: Self.swapGB(),
            diskFreePercent: Self.diskFreePercent(),
            browserTabs: cachedTabs,
            openApps: NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.count,
            frontApp: front,
            frontAppMinutes: now.timeIntervalSince(frontSince) / 60,
            workMinutes: idle >= Self.breakSeconds ? 0 : now.timeIntervalSince(workStart) / 60,
            idleSeconds: idle,
            uptimeDays: Self.uptimeDays(),
            hour: Calendar.current.component(.hour, from: now)
        )
    }

    // MARK: CPU

    private func smoothedCPU() -> Double {
        guard let ticks = Self.cpuTicks() else { return cpuHistory.last ?? 0 }
        defer { lastTicks = ticks }
        guard let last = lastTicks, ticks.total > last.total else { return cpuHistory.last ?? 0 }
        let pct = Double(ticks.busy - last.busy) / Double(ticks.total - last.total) * 100
        cpuHistory.append(pct)
        if cpuHistory.count > 3 { cpuHistory.removeFirst() }
        return cpuHistory.reduce(0, +) / Double(cpuHistory.count)
    }

    private static func cpuTicks() -> (busy: UInt64, total: UInt64)? {
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &load) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let user = UInt64(load.cpu_ticks.0), system = UInt64(load.cpu_ticks.1)
        let idle = UInt64(load.cpu_ticks.2), nice = UInt64(load.cpu_ticks.3)
        return (user + system + nice, user + system + nice + idle)
    }

    // MARK: Heat, battery

    private static func thermal() -> Thermal {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .nominal
        }
    }

    private static func battery() -> Battery? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  (desc[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType,
                  let current = desc[kIOPSCurrentCapacityKey] as? Int,
                  let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0
            else { continue }
            let onAC = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let charging = desc[kIOPSIsChargingKey] as? Bool ?? false
            return Battery(percent: Int((Double(current) / Double(max) * 100).rounded()), onAC: onAC, charging: charging)
        }
        return nil
    }

    // MARK: Memory, disk

    private static func memory() -> (Double, MemoryPressure) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        var percent = 0.0
        if result == KERN_SUCCESS {
            let page = Double(sysconf(_SC_PAGESIZE))
            // Roughly Activity Monitor's "Memory Used": app memory + wired + compressed.
            let anonymous = Double(stats.internal_page_count) - Double(stats.purgeable_count)
            let used = (anonymous + Double(stats.wire_count) + Double(stats.compressor_page_count)) * page
            percent = min(100, max(0, used / Double(ProcessInfo.processInfo.physicalMemory) * 100))
        }

        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0)
        let pressure: MemoryPressure = switch level {
        case 4: .critical
        case 2: .warning
        default: .normal
        }
        return (percent, pressure)
    }

    private static func swapGB() -> Double {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return 0 }
        return Double(usage.xsu_used) / 1_073_741_824
    }

    private static func diskFreePercent() -> Double {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let free = values.volumeAvailableCapacityForImportantUsage,
              let total = values.volumeTotalCapacity, total > 0
        else { return 100 }
        return Double(free) / Double(total) * 100
    }

    // MARK: Time

    private static func idleSeconds() -> Double {
        // ~0 is kCGAnyInputEventType: keyboard, mouse or trackpad.
        guard let any = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: any)
    }

    private static func uptimeDays() -> Double {
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0 else { return 0 }
        return (Date().timeIntervalSince1970 - Double(boot.tv_sec)) / 86400
    }
}

/// Counts open tabs in running browsers with AppleScript. macOS asks once per browser for permission.
@MainActor
final class TabCounter {
    private static let browsers: [(bundleID: String, script: String)] = [
        ("com.google.Chrome", "Google Chrome"),
        ("com.brave.Browser", "Brave Browser"),
        ("com.microsoft.edgemac", "Microsoft Edge"),
        ("company.thebrowser.Browser", "Arc"),
        ("com.apple.Safari", "Safari"),
    ]

    func count() -> Int? {
        var total = 0
        var answered = false
        for browser in Self.browsers {
            // Only ask running browsers: AppleScript would launch a closed one.
            guard !NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleID).isEmpty else { continue }
            let source = """
            tell application id "\(browser.bundleID)"
                set n to 0
                repeat with w in windows
                    set n to n + (count of tabs of w)
                end repeat
                return n
            end tell
            """
            var error: NSDictionary?
            if let result = NSAppleScript(source: source)?.executeAndReturnError(&error), error == nil {
                total += Int(result.int32Value)
                answered = true
            }
        }
        return answered ? total : nil
    }
}
