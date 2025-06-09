const std = @import("std");
const testing = std.testing;

// +----- Database -----+

const DbError = std.fs.Dir.OpenError || std.fs.Dir.MakeError;

const DB = struct {
    const Self = @This();
    dir: std.fs.Dir,

    /// Creates or Updates a table using a custom Struct.
    pub fn table(self: *Self, comptime T: type) !Table(T) {
        var tbl = Table(T).init(self);
        if (try tbl.exists() and try tbl.changed()) {
            try tbl.replace();
        } else if (!try tbl.exists()) {
            try tbl.create();
        }
        return tbl;
    }
};

/// Opens a Database directory.
/// Creates the directory if it doesn't exist
///
/// args:
/// - name: []u8 `Directory path to database directory from current directory`
pub fn open(name: []const u8) DbError!DB {
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
    comptime if (struct_fields.len > 255) @panic("Tables can't have more than 255 fields.");
    comptime for (struct_fields) |f| if (f.name.len > 255) @panic("Table fields can't have more than 255 characters");
    // Table Struct
    return struct {
        const Self = @This();
        db: *DB,

        /// Initializes the table with a corresponding Database.
        /// If no Database is available, no tables can be found.
        pub fn init(db: *DB) Self {
            return Self{ .db = db };
        }
        /// Checks if a table exists
        pub fn exists(self: *Self) TableError!bool {
            self.db.dir.access(@typeName(T), .{ .mode = .read_only }) catch return false;
            return true;
        }
        /// Checks if the definition of the table has changed
        pub fn changed(self: *Self) !bool {
            // TODO
            _ = self;
            return true;
        }
        /// Right now, replacing/updating, deletes all the data
        pub fn replace(self: *Self) !void {
            try self.db.dir.deleteFile(@typeName(T));
            return self.create();
        }
        /// Create The Table on Disk
        pub fn create(self: *Self) !void {
            // create file

            const tbl_file = self.db.dir.openFile(@typeName(T), .{ .mode = .write_only }) catch blk: {
                break :blk try self.db.dir.createFile(@typeName(T), .{});
            };
            // initialize row count with 0
            _ = try tbl_file.write(&[_]u8{ 0, 0, 0, 0, 0, 0, 0, 0 });
            // write length of colums
            const fields = @typeInfo(T).@"struct".fields;
            _ = try tbl_file.write(&[_]u8{@as(u8, fields.len)});
            // columns
            inline for (fields) |f| {
                // column length
                _ = try tbl_file.write(&[_]u8{@as(u8, f.name.len)}); // column type
                const col_type = DbType.from_type(f.type);
                _ = try tbl_file.write(&[_]u8{col_type.to_int()});
                // column name
                _ = try tbl_file.write(f.name);
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
    pub fn from_type(comptime T: type) Self {
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
    pub fn to_type(self: Self) type {
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
    pub fn to_int(self: Self) u8 {
        return @intFromEnum(self);
    }
};
