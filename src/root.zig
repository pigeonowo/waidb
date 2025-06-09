const std = @import("std");
const testing = std.testing;

// +----- Database -----+

const DBError = std.fs.Dir.OpenError || std.fs.Dir.MakeError;

const DB = struct {
    const Self = @This();
    dir: std.fs.Dir,

    /// Creates or Updates a table using a custom Struct.
    fn table(self: *Self, comptime T: type) Table(T) {
        const tbl = Table(T).init(self);
        if (try tbl.exists() and try tbl.table_changed()) {
            try tbl.replace_table();
        } else if (!tbl.table_exists()) {
            try tbl.create_table();
        }
        return tbl;
    }
};

/// Opens a Database directory.
/// Creates the directory if it doesn't exist
///
/// args:
/// - name: []u8 `Directory path to database directory from current directory`
pub fn open(name: []u8) DBError!DB {
    const cur_dir = std.fs.cwd();
    const db_dir = cur_dir.openDir(name, .{}) catch mkdir: {
        try cur_dir.makeDir(name);
        break :mkdir try cur_dir.openDir(name, .{});
    };
    return DB{ .dir = db_dir };
}

// +----- TABLES -----+
// Tabbles are single files under a Database directory.

const TableError = error{noDatabase};

pub fn Table(comptime T: type) type {
    return struct {
        const Self = @This();
        type: type,
        db: *DB,

        /// Initializes the table with a corresponding Database.
        /// If no Database is available, no tables can be found.
        fn init(db: *DB) Self {
            return Self{ .type = T, .db = db };
        }
        fn exists(self: *Self) TableError!bool {
            self.db.dir.access(@typeName(self.type), .{ .mode = .read_only }) catch return false;
            return true;
        }
        fn changed(self: *Self) !bool {}
        fn replace(self: *Self) !void {}
        fn create(self: *Self) !void {}
    };
}
