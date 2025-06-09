const std = @import("std");

pub const Insert = struct {
    const Self = @This();
    executor: CommandExecutor,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{ .allocator = allocator, .executor = CommandExecutor.init(allocator) };
    }

    // pub fn field(...)
};

pub const Command = union(enum) {
    insert: []u8, // tablename
    nop: void,
    stop: void, // tells the CommandExecutor to stop
};

// TODO: make better
const CommandResult = enum { ok, err };

pub const CommandExecutor = struct {
    const Self = @This();
    const COMMAND_BUF_SIZE: usize = 512;
    cmds: [COMMAND_BUF_SIZE]Command, // maybe later with more complex commands it needs to be managed by an allocator
    cmd_ptr: usize = 0,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{ .cmds = .{Command.stop} ** 512, .allocator = allocator };
    }

    pub fn step(self: *Self) ?CommandResult {
        if (!(self.cmd_ptr < COMMAND_BUF_SIZE)) {
            return null;
        }
        defer self.cmd_ptr += 1;
        return switch (self.cmds[self.cmd_ptr]) {
            Command.stop => null,
            Command.nop => CommandResult.ok,
            else => CommandResult.err,
        };
    }

    pub fn run(self: *Self) void {
        while (self.step()) |_| {}
    }
};
