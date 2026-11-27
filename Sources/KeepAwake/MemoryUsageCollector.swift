import Foundation
import Darwin

enum MemoryUsageCollector {
    static func sample() -> UInt64? {
        var statistics = vm_statistics64_data_t()

        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size /
            MemoryLayout<integer_t>.size
        )

        let host = mach_host_self()

        defer {
            mach_port_deallocate(mach_task_self_, host)
        }

        let result = withUnsafeMutablePointer(
            to: &statistics
        ) { pointer in
            pointer.withMemoryRebound(
                to: integer_t.self,
                capacity: Int(count)
            ) { reboundPointer in
                host_statistics64(
                    host,
                    HOST_VM_INFO64,
                    reboundPointer,
                    &count
                )
            }
        }

        guard result == KERN_SUCCESS else {
            return nil
        }

        let pageSize = UInt64(vm_kernel_page_size)

        let internalPages = UInt64(
            statistics.internal_page_count
        )

        let purgeablePages = UInt64(
            statistics.purgeable_count
        )

        let applicationPages =
            internalPages > purgeablePages
            ? internalPages - purgeablePages
            : 0

        let wiredPages = UInt64(
            statistics.wire_count
        )

        let compressedPages = UInt64(
            statistics.compressor_page_count
        )

        let usedPages =
            applicationPages +
            wiredPages +
            compressedPages

        return min(
            ProcessInfo.processInfo.physicalMemory,
            usedPages * pageSize
        )
    }
}