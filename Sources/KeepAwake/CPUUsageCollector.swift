import Foundation
import Darwin

final class CPUUsageCollector {
    private var previous: [UInt32]?

    func sample() -> Double? {
        var info = host_cpu_load_info_data_t()

        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size /
            MemoryLayout<integer_t>.size
        )

        let host = mach_host_self()

        defer {
            mach_port_deallocate(mach_task_self_, host)
        }

        let result = withUnsafeMutablePointer(
            to: &info
        ) { pointer in
            pointer.withMemoryRebound(
                to: integer_t.self,
                capacity: Int(count)
            ) { reboundPointer in
                host_statistics(
                    host,
                    HOST_CPU_LOAD_INFO,
                    reboundPointer,
                    &count
                )
            }
        }

        guard result == KERN_SUCCESS else {
            previous = nil
            return nil
        }

        let current: [UInt32] = [
            info.cpu_ticks.0,
            info.cpu_ticks.1,
            info.cpu_ticks.2,
            info.cpu_ticks.3
        ]

        defer {
            previous = current
        }

        guard let previous else {
            return nil
        }

        let user = UInt64(current[0] &- previous[0])
        let system = UInt64(current[1] &- previous[1])
        let idle = UInt64(current[2] &- previous[2])
        let nice = UInt64(current[3] &- previous[3])

        let busy = user + system + nice
        let total = busy + idle

        guard total > 0 else {
            return nil
        }

        return min(
            100,
            max(
                0,
                Double(busy) / Double(total) * 100
            )
        )
    }

    func reset() {
        previous = nil
    }
}