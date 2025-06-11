const std = @import("std");
const testing = std.testing;

// +----- Database -----+

const DbError = std.fs.Dir.OpenError || std.fs.Dir.MakeError;

const DB = struct {
    const Self = @This();
    dir: std.fs.Dir,

    /// Creates or Updates a table using a custom Struct.
    pub fn table(self: *Self, comptime T: type) !Table(T, @typeName(T)) {
        var tbl = Table(T, @typeName(T)).init(self);
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

test "open DB" {
    const db = try open("_test");
    _ = db;
    try std.fs.cwd().deleteDir("_test");
}

// +----- TABLES -----+
// Tabbles are single files under a Database directory.

const TableError = error{noDatabase};

pub const TableCol = struct {
    name: []const u8,
    t: DbType,
};

pub fn Table(comptime T: type, name: []const u8) type {
    // validation
    const struct_fields = @typeInfo(T).@"struct".fields;
    comptime if (struct_fields.len > 255) @panic("Tables can't have more than 255 fields.");
    comptime for (struct_fields) |f| if (f.name.len > 255) @panic("Table fields can't have more than 255 characters");
    // Table Struct
    return struct {
        const Self = @This();
        name: []const u8,
        db: *DB,

        /// Initializes the table with a corresponding Database.
        /// If no Database is available, no tables can be found.
        pub fn init(db: *DB) Self {
            var dot_index: usize = 0;
            var i: usize = 0;
            while (i < name.len) : (i += 1) {
                if (name[i] == '.' and i != name.len - 1) {
                    dot_index = i + 1;
                }
            }
            const t_name = name[dot_index..];
            return Self{ .db = db, .name = t_name };
        }
        /// Checks if a table exists
        pub fn exists(self: *Self) TableError!bool {
            self.db.dir.access(self.name, .{ .mode = .read_only }) catch return false;
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
            try self.db.dir.deleteFile(self.name);
            return self.create();
        }
        /// Create The Table on Disk
        pub fn create(self: *Self) !void {
            // create file
            var tbl_file = try self.get_file();
            defer tbl_file.close();
            // HEADER
            // initialize row count with 0
            _ = try tbl_file.write(&[_]u8{ 0, 0, 0, 0, 0, 0, 0, 0 });
            // write length of colums
            const fields = @typeInfo(T).@"struct".fields;
            _ = try tbl_file.write(&[_]u8{@as(u8, fields.len)});
            // columns
            inline for (fields) |f| {
                // column type
                const col_type = DbType.from_type(f.type);
                _ = try tbl_file.write(&[_]u8{col_type.to_int()});
                // column length
                _ = try tbl_file.write(&[_]u8{@as(u8, f.name.len)});
                // column name
                _ = try tbl_file.write(f.name);
            }
        }

        fn get_file(self: *Self) !std.fs.File {
            return self.db.dir.openFile(self.name, .{ .mode = .write_only }) catch blk: {
                break :blk try self.db.dir.createFile(self.name, .{});
            };
        }

        pub fn table_info(self: *Self, allocator: std.mem.Allocator) ![]TableCol {
            var tbl_file = try self.get_file();
            defer tbl_file.close();
            // skip row count
            try tbl_file.seekTo(8);
            // get col length
            var col_length_buf: [1]u8 = .{0};
            try tbl_file.read(&col_length_buf);
            const col_length = col_length_buf[0];
            var table_cols: []TableCol = try allocator.alloc(TableCol, @as(usize, col_length)); // do we need to alloc when 0?
            for (0..col_length) |i| {
                // type
                var col_type_buf: [1]u8 = undefined;
                try tbl_file.read(&col_type_buf);
                const col_type = DbType.from_int(col_type_buf[0]);
                // name len
                var col_name_len_buf: [1]u8 = undefined;
                try tbl_file.read(&col_name_len_buf);
                const col_name_len = col_name_len_buf[0];
                // name
                const col_name: []u8 = try allocator.alloc(u8, @as(usize, col_name_len));
                try tbl_file.read(col_name);
                table_cols[i] = TableCol{ .t = col_type, .name = col_name };
            }
            return table_cols;
        }
    };
}

test "create table" {
    const test_table = struct { age: u8, name: []u8 };
    var db = try open("_test_create_table");
    const table = try db.table(test_table);
    _ = table;
    var is_inside = false;
    var db_dir = try std.fs.cwd().openDir("_test_create_table", .{ .iterate = true });
    var iter = db_dir.iterate();
    while (try iter.next()) |f| {
        if (std.mem.eql(u8, f.name, "test_table")) {
            is_inside = true;
        }
    }
    try testing.expect(is_inside);
    try db_dir.deleteFile("test_table");
    try std.fs.cwd().deleteDir("_test_create_table");
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

    pub fn from_int(i: u8) Self {
        return @enumFromInt(i);
    }
};

// +----- Commands -----+

pub const Insert = struct {
    const Self = @This();
    executor: CommandExecutor,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{ .allocator = allocator, .executor = CommandExecutor.init(allocator) };
    }

    // pub fn field(...)
};

// +----- Command "VM" -----+

pub const Command = union(enum) {
    insert: void,
    table_context: []u8, // tablename
    field: []u8, // field name
    field_value: []u8,
    field_type: []u8,
    nop: void,
    stop: void, // tells the CommandExecutor to stop
};

// TODO: make better
// a result for select, insert, etc
const CommandResult = union(enum) { ok: void, err: []const u8, insert: enum { ok, err } };

pub const CommandExecutor = struct {
    const Self = @This();
    cmds: []Command,
    cmd_ptr: usize = 0,
    db_context: ?[]u8 = null,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, cmds: []Command) Self {
        return Self{ .cmds = cmds, .allocator = allocator };
    }

    pub fn next_command(self: *Self) ?CommandResult {
        if (!(self.cmd_ptr < self.cmds.len)) {
            return null;
        }
        const cmd = self.cmds[self.cmd_ptr];
        self.cmd_ptr += 1;
        return cmd;
    }
    pub fn run(self: *Self) ?CommandResult {
        var result: ?CommandResult = .ok;
        while (self.next_command()) |cmd| {
            result = switch (cmd) {
                Command.stop => .ok,
                Command.nop => .ok,
                Command.db_context => |db| self.db_context = db,
                Command.insert => if (self.db_context) {
                    const ih = InsertHandler.init(self);
                    return ih.run();
                } else {
                    // @panic("No DB context set")
                    return .{ .err = "No DB context set" };
                },
                else => return .{ .err = "Not a valid Command" },
            };
        } else {
            return .ok;
        }
        return result;
    }

    const InsertHandler = struct {
        executor: *CommandExecutor,
        tbl_context: ?[]u8,
        tbl_cols: ?[]TableCol,

        pub fn init(e: *CommandExecutor) @This() {
            return InsertHandler{ .executor = e, .tbl_context = null };
        }

        pub fn run(self: *@This()) CommandResult.insert {
            var result: CommandResult = .{ .insert = .err };
            w: while (self.executor.next_command()) |cmd| {
                switch (cmd) {
                    Command.table_context => |tbl| {
                        self.tbl_context = tbl;
                        const db = open(self.executor.db_context) catch return .{ .insert = .err };
                        self.tbl_cols = Table(.{}, tbl).init(&db).table_info(self.executor.allocator);
                    },
                    Command.field => {},
                    else => {
                        result = .{ .insert = .err };
                        break :w;
                    },
                }
            }
            return result;
        }
    };
};
