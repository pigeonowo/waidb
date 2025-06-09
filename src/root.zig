const std = @import("std");
const testing = std.testing;

// +----- Database -----+

const DbError = std.fs.Dir.OpenError || std.fs.Dir.MakeError;

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
pub fn open(name: []u8) DbError!DB {
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
    // validation
    const struct_fields = @typeInfo(T).@"struct".fields;
    if (struct_fields.len > 255) @panic("Tables can't have more than 255 fields.");
    for (struct_fields) |f| if (f.name.len > 255) @panic("Table fields can't have more than 255 characters");
    // Table Struct
    return struct {
        const Self = @This();
        type: type,
        db: *DB,

        /// Initializes the table with a corresponding Database.
        /// If no Database is available, no tables can be found.
        fn init(db: *DB) Self {
            return Self{ .type = T, .db = db };
        }
        /// Checks if a table exists
        fn exists(self: *Self) TableError!bool {
            self.db.dir.access(@typeName(self.type), .{ .mode = .read_only }) catch return false;
            return true;
        }
        /// Checks if the definition of the table has changed
        fn changed(self: *Self) !bool {
            // TODO
            _ = self;
            return true;
        }
        /// Right now, replacing/updating, deletes all the data
        fn replace(self: *Self) !void {
            try self.db.dir.deleteFile(@typeName(self.type));
            return self.create();
        }
        /// Create The Table on Disk
        fn create(self: *Self) !void {
            // create file
            const tbl_file = try self.db.dir.openFile(@typeName(self.type), .{ .mode = .write_only });
            // initialize row count with 0
            try tbl_file.write([_]u8{ 0, 0, 0, 0, 0, 0, 0, 0 });
            // write length of colums
            const fields = @typeInfo(self.type).@"struct".fields;
            try tbl_file.write([_]u8{@as(u8, fields.len)});
            // columns
            inline for (fields) |f| {
                // column length
                try tbl_file.write([_]u8{@as(u8, f.name.len)});
                // column type
                const col_type = DbType.from_type(f.type);
                try tbl_file.write([_]u8{col_type.to_int()});
                // column name
                try tbl_file.write(f.name);
            }
        }
    };
}

// +----- Types -----+

const DbType = enum(u8) {
    const Self = @This();
    // Numbers
    t_u8 = 1,
    t_u16 = 2,
    t_u32 = 3,
    t_u64 = 4,
    t_u128 = 5,
    t_i8 = 6,
    t_i16 = 7,
    t_i32 = 8,
    t_i64 = 9,
    t_i128 = 10,
    // string-like
    t_string = 11,
    fn from_type(comptime T: type) Self {
        return switch (T) {
            u8 => .t_u8,
            u16 => .t_u16,
            u32 => .t_u32,
            u64 => .t_u64,
            u128 => .t_u128,
            i8 => .t_i8,
            i16 => .t_i16,
            i32 => .t_i32,
            i64 => .t_i64,
            i128 => .t_i128,
            []u8 => .t_string,
            else => @panic("There is no such Database type"),
        };
    }
    fn to_type(self: Self) type {
        return switch (self) {
            .t_u8 => u8,
            .t_u16 => u16,
            .t_u32 => u32,
            .t_u64 => u64,
            .t_u128 => u128,
            .t_i8 => i8,
            .t_i16 => i16,
            .t_i32 => i32,
            .t_i64 => i64,
            .t_i128 => i128,
            .t_string => []u8,
        };
    }
    fn to_int(self: Self) u8 {
        return @intFromEnum(self);
    }
};
