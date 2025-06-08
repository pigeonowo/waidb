const std = @import("std");
const waidb = @import("waidb_lib");

pub fn main() !void {
    std.debug.print("Test add: {}\n", .{waidb.add(1, 2)});
}
