import Foundation
import GRDB

/// Owns the SQLite database (`DatabasePool` on disk with WAL, or `DatabaseQueue` in memory for tests)
/// and versioned migrations matching PLAN §4.
public final class HoltDatabase: Sendable {
    public let writer: any DatabaseWriter
    public let path: String?

    public init(writer: any DatabaseWriter, path: String? = nil) throws {
        self.writer = writer
        self.path = path
        try Self.migrator.migrate(writer)
    }

    public static func defaultURL() throws -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Holt", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("holt.sqlite")
    }

    public static func openOnDisk(at url: URL? = nil) throws -> HoltDatabase {
        let dbURL = try url ?? defaultURL()
        try FileManager.default.createDirectory(at: dbURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var config = Configuration()
        config.foreignKeysEnabled = true
        let pool = try DatabasePool(path: dbURL.path, configuration: config)
        return try HoltDatabase(writer: pool, path: dbURL.path)
    }

    public static func openInMemory() throws -> HoltDatabase {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let queue = try DatabaseQueue(configuration: config)
        return try HoltDatabase(writer: queue, path: nil)
    }

    public func checkIntegrity() throws -> Bool {
        try writer.read { db in
            let result = try String.fetchOne(db, sql: "PRAGMA integrity_check")
            return result == "ok"
        }
    }

    // MARK: - Migrations

    public static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_core_tasks_sessions") { db in
            try db.execute(sql: """
                CREATE TABLE setting (
                    key TEXT PRIMARY KEY,
                    value TEXT NOT NULL
                );

                CREATE TABLE list (
                    id INTEGER PRIMARY KEY,
                    name TEXT NOT NULL,
                    color TEXT,
                    icon TEXT,
                    sort INTEGER NOT NULL DEFAULT 0,
                    archived_at INTEGER
                );

                CREATE TABLE task (
                    id INTEGER PRIMARY KEY,
                    list_id INTEGER REFERENCES list(id),
                    title TEXT NOT NULL,
                    notes TEXT,
                    day TEXT NOT NULL,
                    status TEXT NOT NULL CHECK (status IN ('todo','doing','done','skipped','abandoned')),
                    priority INTEGER NOT NULL DEFAULT 0,
                    estimate_pomos INTEGER,
                    link TEXT,
                    recurrence TEXT,
                    carried_from_id INTEGER REFERENCES task(id),
                    root_id INTEGER REFERENCES task(id),
                    created_at INTEGER NOT NULL,
                    completed_at INTEGER,
                    skip_reason TEXT
                );
                CREATE INDEX task_day ON task(day);
                CREATE INDEX task_root ON task(root_id);

                CREATE TABLE task_event (
                    id INTEGER PRIMARY KEY,
                    task_id INTEGER NOT NULL REFERENCES task(id) ON DELETE CASCADE,
                    ts INTEGER NOT NULL,
                    kind TEXT NOT NULL,
                    meta TEXT
                );

                CREATE TABLE note (
                    id INTEGER PRIMARY KEY,
                    day TEXT NOT NULL,
                    task_id INTEGER,
                    session_id INTEGER,
                    body TEXT NOT NULL,
                    created_at INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL
                );
                CREATE INDEX note_day ON note(day);

                CREATE TABLE session (
                    id INTEGER PRIMARY KEY,
                    kind TEXT NOT NULL CHECK (kind IN ('work','short_break','long_break')),
                    planned_sec INTEGER NOT NULL,
                    cycle_index INTEGER NOT NULL,
                    task_id INTEGER REFERENCES task(id) ON DELETE SET NULL,
                    started_at INTEGER NOT NULL,
                    ended_at INTEGER,
                    end_reason TEXT,
                    active_sec INTEGER NOT NULL DEFAULT 0,
                    started_by TEXT NOT NULL DEFAULT 'user'
                );
                CREATE INDEX session_started ON session(started_at);

                CREATE TABLE session_pause (
                    id INTEGER PRIMARY KEY,
                    session_id INTEGER NOT NULL REFERENCES session(id) ON DELETE CASCADE,
                    started_at INTEGER NOT NULL,
                    ended_at INTEGER,
                    reason TEXT NOT NULL
                );
            """)

            let defaults: [(String, String, String, Int)] = [
                ("Work", "#F97316", "briefcase.fill", 0),
                ("Personal", "#6366F1", "person.fill", 1),
                ("Health", "#10B981", "heart.fill", 2),
                ("Study", "#3B82F6", "book.fill", 3),
                ("Admin", "#8B5CF6", "tray.full.fill", 4),
                ("Errands", "#EC4899", "cart.fill", 5),
            ]
            for (name, color, icon, sort) in defaults {
                try db.execute(
                    sql: "INSERT INTO list (name, color, icon, sort) VALUES (?, ?, ?, ?)",
                    arguments: [name, color, icon, sort]
                )
            }
        }

        migrator.registerMigration("v2_tracking_stats_voice") { db in
            try db.execute(sql: """
                CREATE TABLE app_span (
                    id INTEGER PRIMARY KEY,
                    bundle_id TEXT NOT NULL,
                    app_name TEXT NOT NULL,
                    window_title TEXT,
                    started_at INTEGER NOT NULL,
                    ended_at INTEGER NOT NULL,
                    session_id INTEGER,
                    session_kind TEXT,
                    idle INTEGER NOT NULL DEFAULT 0,
                    category TEXT
                );
                CREATE INDEX app_span_time ON app_span(started_at);

                CREATE TABLE web_span (
                    id INTEGER PRIMARY KEY,
                    app_span_id INTEGER REFERENCES app_span(id) ON DELETE SET NULL,
                    browser TEXT NOT NULL,
                    url TEXT,
                    domain TEXT NOT NULL,
                    title TEXT,
                    yt_video_id TEXT,
                    yt_channel TEXT,
                    yt_category TEXT,
                    started_at INTEGER NOT NULL,
                    ended_at INTEGER NOT NULL,
                    session_id INTEGER,
                    session_kind TEXT,
                    category TEXT,
                    category_source TEXT
                );
                CREATE INDEX web_span_time ON web_span(started_at);

                CREATE TABLE screen_observation (
                    id INTEGER PRIMARY KEY,
                    ts INTEGER NOT NULL,
                    session_id INTEGER,
                    bundle_id TEXT,
                    label TEXT,
                    on_task TEXT,
                    confidence REAL,
                    keywords TEXT
                );
                CREATE INDEX screen_observation_ts ON screen_observation(ts);

                CREATE TABLE category_rule (
                    id INTEGER PRIMARY KEY,
                    kind TEXT NOT NULL,
                    pattern TEXT NOT NULL,
                    category TEXT NOT NULL,
                    source TEXT NOT NULL,
                    UNIQUE(kind, pattern)
                );

                CREATE TABLE procrastination_event (
                    id INTEGER PRIMARY KEY,
                    ts INTEGER NOT NULL,
                    session_id INTEGER,
                    kind TEXT NOT NULL,
                    subject TEXT,
                    duration_sec INTEGER,
                    severity INTEGER NOT NULL
                );

                CREATE TABLE holt_message (
                    id INTEGER PRIMARY KEY,
                    ts INTEGER NOT NULL,
                    channel TEXT NOT NULL,
                    trigger TEXT NOT NULL,
                    tone REAL NOT NULL,
                    template_id TEXT NOT NULL,
                    text TEXT NOT NULL,
                    delivered_at INTEGER,
                    outcome TEXT
                );

                CREATE TABLE daily_rollup (
                    day TEXT PRIMARY KEY,
                    focus_sec INTEGER NOT NULL DEFAULT 0,
                    break_sec INTEGER NOT NULL DEFAULT 0,
                    idle_sec INTEGER NOT NULL DEFAULT 0,
                    sessions_done INTEGER NOT NULL DEFAULT 0,
                    sessions_abandoned INTEGER NOT NULL DEFAULT 0,
                    tasks_planned INTEGER NOT NULL DEFAULT 0,
                    tasks_done INTEGER NOT NULL DEFAULT 0,
                    tasks_skipped INTEGER NOT NULL DEFAULT 0,
                    distract_sec INTEGER NOT NULL DEFAULT 0,
                    switches INTEGER NOT NULL DEFAULT 0,
                    focus_score INTEGER NOT NULL DEFAULT 0,
                    top_app TEXT,
                    top_site TEXT,
                    computed_at INTEGER NOT NULL
                );

                CREATE TABLE hourly_rollup (
                    day TEXT NOT NULL,
                    hour INTEGER NOT NULL,
                    focus_sec INTEGER NOT NULL DEFAULT 0,
                    distract_sec INTEGER NOT NULL DEFAULT 0,
                    PRIMARY KEY (day, hour)
                );
            """)
        }

        return migrator
    }
}
