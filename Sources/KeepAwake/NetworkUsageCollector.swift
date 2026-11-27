import Foundation
import Darwin

final class NetworkUsageCollector {
    private var previous: [String: ResourceCounters] = [:]
    private var previousTime: TimeInterval?

    func sample() -> (
        download: Double,
        upload: Double
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

        var downloaded: UInt64 = 0
        var uploaded: UInt64 = 0

        for (name, counters) in current {
            guard let old = previous[name] else {
                continue
            }

            guard counters.read >= old.read,
                  counters.written >= old.written else {
                continue
            }

            downloaded += counters.read - old.read
            uploaded += counters.written - old.written
        }

        return (
            Double(downloaded) / elapsed,
            Double(uploaded) / elapsed
        )
    }

    private func readCounters()
        -> [String: ResourceCounters]? {

        var interfaces: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&interfaces) == 0,
              let first = interfaces else {
            return nil
        }

        defer {
            freeifaddrs(first)
        }

        var result: [String: ResourceCounters] = [:]

        var pointer: UnsafeMutablePointer<ifaddrs>? =
            first

        while let current = pointer {
            let interface = current.pointee
            pointer = interface.ifa_next

            guard let address = interface.ifa_addr,
                  Int32(address.pointee.sa_family) == AF_LINK,
                  let data = interface.ifa_data else {
                continue
            }

            let flags = interface.ifa_flags

            guard flags & UInt32(IFF_UP) != 0,
                  flags & UInt32(IFF_RUNNING) != 0,
                  flags & UInt32(IFF_LOOPBACK) == 0 else {
                continue
            }

            let name = String(
                cString: interface.ifa_name
            )

            // Physical Ethernet and Wi-Fi interfaces.
            // Exclude VPN tunnels and virtual interfaces
            // to reduce double counting.
            guard name.hasPrefix("en") else {
                continue
            }

            let counters = data.assumingMemoryBound(
                to: if_data.self
            ).pointee

            result[name] = ResourceCounters(
                read: UInt64(counters.ifi_ibytes),
                written: UInt64(counters.ifi_obytes)
            )
        }

        return result
    }

    func reset() {
        previous.removeAll()
        previousTime = nil
    }
}