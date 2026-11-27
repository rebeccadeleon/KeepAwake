import Foundation
import IOKit

final class DiskUsageCollector {
    private var previous: [UInt64: ResourceCounters] = [:]
    private var previousTime: TimeInterval?

    func sample() -> (
        read: Double,
        write: Double
    )? {
        guard let current = readCounters() else {
            reset()
            return nil
        }

        let now = ProcessInfo.processInfo.systemUptime

        defer {
            previous = current
            previousTime = now
        }

        guard let previousTime else {
            return nil
        }

        let elapsed = now - previousTime

        guard elapsed > 0 else {
            return nil
        }

        var readBytes: UInt64 = 0
        var writtenBytes: UInt64 = 0

        for (id, counters) in current {
            guard let old = previous[id] else {
                continue
            }

            guard counters.read >= old.read,
                  counters.written >= old.written else {
                continue
            }

            readBytes += counters.read - old.read
            writtenBytes += counters.written - old.written
        }

        return (
            Double(readBytes) / elapsed,
            Double(writtenBytes) / elapsed
        )
    }

    private func readCounters()
        -> [UInt64: ResourceCounters]? {

        guard let matching = IOServiceMatching(
            "IOBlockStorageDriver"
        ) else {
            return nil
        }

        var iterator: io_iterator_t = 0

        let result = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            matching,
            &iterator
        )

        guard result == KERN_SUCCESS else {
            return nil
        }

        defer {
            IOObjectRelease(iterator)
        }

        var counters: [UInt64: ResourceCounters] = [:]

        while true {
            let service = IOIteratorNext(iterator)

            guard service != 0 else {
                break
            }

            defer {
                IOObjectRelease(service)
            }

            var registryID: UInt64 = 0

            guard IORegistryEntryGetRegistryEntryID(
                service,
                &registryID
            ) == KERN_SUCCESS else {
                continue
            }

            guard let property =
                IORegistryEntryCreateCFProperty(
                    service,
                    "Statistics" as CFString,
                    kCFAllocatorDefault,
                    0
                )?.takeRetainedValue(),

                let statistics = property
                    as? [String: Any],

                let read = statistics["Bytes (Read)"]
                    as? NSNumber,

                let written = statistics["Bytes (Write)"]
                    as? NSNumber else {
                continue
            }

            counters[registryID] = ResourceCounters(
                read: read.uint64Value,
                written: written.uint64Value
            )
        }

        return counters.isEmpty ? nil : counters
    }

    func reset() {
        previous.removeAll()
        previousTime = nil
    }
}