import Foundation
import Darwin

struct SystemCommandResult: Sendable {
    let output: String
    let succeeded: Bool
}

enum SystemInfoCollector {
    static func command(
        _ executable: String,
        arguments: [String],
        timeout: TimeInterval = 8
    ) async -> SystemCommandResult {
        await Task.detached(priority: .utility) {
            run(
                executable,
                arguments: arguments,
                timeout: timeout
            )
        }.value
    }

    private static func run(
        _ executable: String,
        arguments: [String],
        timeout: TimeInterval
    ) -> SystemCommandResult {
        let process = Process()

        process.executableURL = URL(
            fileURLWithPath: executable
        )

        process.arguments = arguments

        var environment =
            ProcessInfo.processInfo.environment

        environment["LC_ALL"] = "C"
        environment["LANG"] = "C"

        process.environment = environment

        let temporaryURL = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                UUID().uuidString
            )

        guard FileManager.default.createFile(
            atPath: temporaryURL.path,
            contents: nil
        ) else {
            return SystemCommandResult(
                output: "Unable to create diagnostic output.",
                succeeded: false
            )
        }

        defer {
            try? FileManager.default.removeItem(
                at: temporaryURL
            )
        }

        do {
            let handle = try FileHandle(
                forWritingTo: temporaryURL
            )

            defer {
                try? handle.close()
            }

            process.standardOutput = handle
            process.standardError = handle

            try process.run()

            let deadline = ProcessInfo.processInfo
                .systemUptime + timeout

            while process.isRunning {
                if ProcessInfo.processInfo.systemUptime
                    >= deadline {

                    process.terminate()

                    Thread.sleep(
                        forTimeInterval: 0.2
                    )

                    if process.isRunning {
                        kill(
                            process.processIdentifier,
                            SIGKILL
                        )
                    }

                    process.waitUntilExit()

                    return SystemCommandResult(
                        output: "Command timed out.",
                        succeeded: false
                    )
                }

                Thread.sleep(
                    forTimeInterval: 0.05
                )
            }

            process.waitUntilExit()

            let data = try Data(
                contentsOf: temporaryURL
            )

            let output = String(
                decoding: data,
                as: UTF8.self
            )
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            return SystemCommandResult(
                output: output,
                succeeded:
                    process.terminationStatus == 0
            )

        } catch {
            return SystemCommandResult(
                output: error.localizedDescription,
                succeeded: false
            )
        }
    }

    static func sysctlString(
        _ name: String
    ) -> String {
        var size = 0

        guard sysctlbyname(
            name,
            nil,
            &size,
            nil,
            0
        ) == 0,
        size > 0 else {
            return "Unavailable"
        }

        var buffer = [CChar](
            repeating: 0,
            count: size
        )

        let result = buffer.withUnsafeMutableBufferPointer {
            pointer in

            sysctlbyname(
                name,
                pointer.baseAddress,
                &size,
                nil,
                0
            )
        }

        guard result == 0 else {
            return "Unavailable"
        }

        return buffer.withUnsafeBufferPointer {
            pointer in

            guard let address = pointer.baseAddress else {
                return "Unavailable"
            }

            return String(cString: address)
        }
    }

    static func systemFields() -> [ReportField] {
        let info = ProcessInfo.processInfo

        return [
            ReportField(
                label: "Hardware model",
                value: sysctlString("hw.model")
            ),

            ReportField(
                label: "Processor",
                value: sysctlString(
                    "machdep.cpu.brand_string"
                )
            ),

            ReportField(
                label: "Operating system",
                value: info.operatingSystemVersionString
            ),

            ReportField(
                label: "Logical processors",
                value: String(info.processorCount)
            ),

            ReportField(
                label: "Physical memory",
                value: ByteCountFormatter.string(
                    fromByteCount: Int64(
                        info.physicalMemory
                    ),
                    countStyle: .memory
                )
            ),

            ReportField(
                label: "System uptime",
                value: formatDuration(
                    info.systemUptime
                )
            ),

            ReportField(
                label: "Thermal state",
                value: thermalState(info.thermalState)
            )
        ]
    }

    static func formatDuration(
        _ seconds: TimeInterval
    ) -> String {
        let formatter = DateComponentsFormatter()

        formatter.allowedUnits = [
            .day,
            .hour,
            .minute,
            .second
        ]

        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 3

        return formatter.string(
            from: max(0, seconds)
        ) ?? "Unavailable"
    }

    private static func thermalState(
        _ state: ProcessInfo.ThermalState
    ) -> String {
        switch state {
        case .nominal:
            return "Normal"

        case .fair:
            return "Fair"

        case .serious:
            return "Serious"

        case .critical:
            return "Critical"

        @unknown default:
            return "Unknown"
        }
    }
}