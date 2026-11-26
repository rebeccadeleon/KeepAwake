import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(
    -1,
    to: sqlite3_destructor_type.self
)

final class ActivityHistoryStore {
    private var db: OpaquePointer?

    init() throws {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent(
            "KeepAwake",
            isDirectory: true
        )

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let databaseURL = directory
            .appendingPathComponent("activity.sqlite3")

        guard sqlite3_open(
            databaseURL.path,
            &db
        ) == SQLITE_OK else {
            let error = databaseError()
            sqlite3_close(db)
            db = nil
            throw error
        }

        sqlite3_busy_timeout(db, 3000)

        do {
            try execute("PRAGMA journal_mode = WAL;")

            try execute("""
                CREATE TABLE IF NOT EXISTS activity_events (
                    id TEXT PRIMARY KEY,
                    timestamp REAL NOT NULL,
                    type TEXT NOT NULL,
                    detail TEXT NOT NULL
                );
                """)

            try execute("""
                CREATE INDEX IF NOT EXISTS idx_activity_timestamp
                ON activity_events(timestamp DESC);
                """)

            try execute("""
                CREATE TABLE IF NOT EXISTS awake_intervals (
                    id TEXT PRIMARY KEY,
                    started_at REAL NOT NULL,
                    ended_at REAL,
                    last_seen REAL NOT NULL
                );
                """)

            try execute("""
                CREATE INDEX IF NOT EXISTS idx_awake_started
                ON awake_intervals(started_at);
                """)

            // Recover intervals left open by crashes
            // or unexpected application termination.
            try execute("""
                UPDATE awake_intervals
                SET ended_at = last_seen
                WHERE ended_at IS NULL;
                """)

        } catch {
            sqlite3_close(db)
            db = nil
            throw error
        }
    }

    deinit {
        sqlite3_close(db)
    }

    private func databaseError() -> NSError {
        let message: String

        if let db {
            message = String(
                cString: sqlite3_errmsg(db)
            )
        } else {
            message = "SQLite database unavailable."
        }

        return NSError(
            domain: "KeepAwake.ActivityHistory",
            code: Int(sqlite3_errcode(db)),
            userInfo: [
                NSLocalizedDescriptionKey: message
            ]
        )
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(
            db,
            sql,
            nil,
            nil,
            nil
        ) == SQLITE_OK else {
            throw databaseError()
        }
    }

    private func prepare(
        _ sql: String
    ) throws -> OpaquePointer {
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(
            db,
            sql,
            -1,
            &statement,
            nil
        ) == SQLITE_OK,
        let statement else {
            throw databaseError()
        }

        return statement
    }

    private func bind(
        _ value: String,
        to statement: OpaquePointer,
        at index: Int32
    ) {
        _ = value.withCString { pointer in
            sqlite3_bind_text(
                statement,
                index,
                pointer,
                -1,
                sqliteTransient
            )
        }
    }

    private func text(
        _ statement: OpaquePointer,
        _ index: Int32
    ) -> String {
        guard let pointer = sqlite3_column_text(
            statement,
            index
        ) else {
            return ""
        }

        return String(cString: pointer)
    }

    private func step(
        _ statement: OpaquePointer
    ) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw databaseError()
        }
    }

    // MARK: - Events

    func insert(
        _ event: ActivityEvent
    ) throws {
        let statement = try prepare("""
            INSERT INTO activity_events
                (id, timestamp, type, detail)
            VALUES (?, ?, ?, ?);
            """)

        defer {
            sqlite3_finalize(statement)
        }

        bind(
            event.id.uuidString,
            to: statement,
            at: 1
        )

        sqlite3_bind_double(
            statement,
            2,
            event.timestamp.timeIntervalSince1970
        )

        bind(
            event.type.rawValue,
            to: statement,
            at: 3
        )

        bind(
            event.detail,
            to: statement,
            at: 4
        )

        try step(statement)
    }

    func fetchEvents(
        since date: Date,
        limit: Int = 5000
    ) throws -> [ActivityEvent] {
        let statement = try prepare("""
            SELECT id, timestamp, type, detail
            FROM activity_events
            WHERE timestamp >= ?
            ORDER BY timestamp DESC
            LIMIT ?;
            """)

        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_double(
            statement,
            1,
            date.timeIntervalSince1970
        )

        sqlite3_bind_int(
            statement,
            2,
            Int32(clamping: limit)
        )

        var events: [ActivityEvent] = []

        while true {
            let result = sqlite3_step(statement)

            if result == SQLITE_DONE {
                break
            }

            guard result == SQLITE_ROW else {
                throw databaseError()
            }

            guard let id = UUID(
                uuidString: text(statement, 0)
            ),
            let type = ActivityType(
                rawValue: text(statement, 2)
            ) else {
                continue
            }

            events.append(
                ActivityEvent(
                    id: id,
                    timestamp: Date(
                        timeIntervalSince1970:
                            sqlite3_column_double(statement, 1)
                    ),
                    type: type,
                    detail: text(statement, 3)
                )
            )
        }

        return events
    }

    func countEvents(
        _ type: ActivityType,
        since date: Date
    ) throws -> Int {
        let statement = try prepare("""
            SELECT COUNT(*)
            FROM activity_events
            WHERE type = ? AND timestamp >= ?;
            """)

        defer {
            sqlite3_finalize(statement)
        }

        bind(
            type.rawValue,
            to: statement,
            at: 1
        )

        sqlite3_bind_double(
            statement,
            2,
            date.timeIntervalSince1970
        )

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw databaseError()
        }

        return Int(
            sqlite3_column_int64(statement, 0)
        )
    }

    // MARK: - Awake intervals

    func beginInterval(
        id: String,
        at date: Date
    ) throws {
        let statement = try prepare("""
            INSERT INTO awake_intervals
                (id, started_at, last_seen)
            VALUES (?, ?, ?);
            """)

        defer {
            sqlite3_finalize(statement)
        }

        bind(id, to: statement, at: 1)

        sqlite3_bind_double(
            statement,
            2,
            date.timeIntervalSince1970
        )

        sqlite3_bind_double(
            statement,
            3,
            date.timeIntervalSince1970
        )

        try step(statement)
    }

    func heartbeat(
        id: String,
        at date: Date
    ) throws {
        let statement = try prepare("""
            UPDATE awake_intervals
            SET last_seen = ?
            WHERE id = ? AND ended_at IS NULL;
            """)

        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_double(
            statement,
            1,
            date.timeIntervalSince1970
        )

        bind(id, to: statement, at: 2)

        try step(statement)
    }

    func endInterval(
        id: String,
        at date: Date
    ) throws {
        let statement = try prepare("""
            UPDATE awake_intervals
            SET ended_at = ?, last_seen = ?
            WHERE id = ? AND ended_at IS NULL;
            """)

        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_double(
            statement,
            1,
            date.timeIntervalSince1970
        )

        sqlite3_bind_double(
            statement,
            2,
            date.timeIntervalSince1970
        )

        bind(id, to: statement, at: 3)

        try step(statement)
    }

    func fetchIntervals(
        since date: Date,
        until now: Date = Date()
    ) throws -> [ActivityInterval] {
        let statement = try prepare("""
            SELECT id, started_at,
                   COALESCE(ended_at, ?)
            FROM awake_intervals
            WHERE COALESCE(ended_at, ?) > ?
              AND started_at < ?
            ORDER BY started_at;
            """)

        defer {
            sqlite3_finalize(statement)
        }

        let timestamp = now.timeIntervalSince1970

        sqlite3_bind_double(statement, 1, timestamp)
        sqlite3_bind_double(statement, 2, timestamp)

        sqlite3_bind_double(
            statement,
            3,
            date.timeIntervalSince1970
        )

        sqlite3_bind_double(statement, 4, timestamp)

        var intervals: [ActivityInterval] = []

        while true {
            let result = sqlite3_step(statement)

            if result == SQLITE_DONE {
                break
            }

            guard result == SQLITE_ROW else {
                throw databaseError()
            }

            intervals.append(
                ActivityInterval(
                    id: text(statement, 0),
                    startedAt: Date(
                        timeIntervalSince1970:
                            sqlite3_column_double(statement, 1)
                    ),
                    endedAt: Date(
                        timeIntervalSince1970:
                            sqlite3_column_double(statement, 2)
                    )
                )
            )
        }

        return intervals
    }

    // MARK: - Maintenance

    func deleteOlderThan(
        _ date: Date
    ) throws {
        let timestamp = date.timeIntervalSince1970

        let events = try prepare("""
            DELETE FROM activity_events
            WHERE timestamp < ?;
            """)

        defer {
            sqlite3_finalize(events)
        }

        sqlite3_bind_double(events, 1, timestamp)
        try step(events)

        let intervals = try prepare("""
            DELETE FROM awake_intervals
            WHERE ended_at IS NOT NULL
              AND ended_at < ?;
            """)

        defer {
            sqlite3_finalize(intervals)
        }

        sqlite3_bind_double(intervals, 1, timestamp)
        try step(intervals)
    }

    func clear() throws {
        try execute("BEGIN TRANSACTION;")

        do {
            try execute("DELETE FROM activity_events;")
            try execute("DELETE FROM awake_intervals;")
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }
}