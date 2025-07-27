const Self = @This();
pub const PortRange = struct { from: u16, to: u16 };

allocator: std.mem.Allocator,

dir: std.fs.Dir,
global_dir: std.fs.Dir,
addr: std.net.Address,
port_range: ?PortRange,
max_bytes: usize,
entries: []const []const u8,

pub fn fromArgs(allocator: std.mem.Allocator, args: arg.ArgRes) errhandl.AllocError!Self {
    const dir: std.fs.Dir = args.args.dir orelse blk: {
        break :blk std.fs.cwd().openDir("./serve", .{}) catch std.fs.cwd();
    };

    const global_dir: std.fs.Dir = args.args.global orelse blk: {
        break :blk std.fs.cwd().openDir("./global", .{}) catch std.fs.cwd();
    };

    var port_range: ?PortRange = args.args.@"port-range" orelse .{ .from = 8000, .to = 9000 };
    // ignore --port-range if --port is supplied
    if (args.args.port) |_|
        port_range = null;

    const port: u16 = args.args.port orelse 8080;
    var addr: std.net.Address = args.args.bind orelse std.net.Address.initIp4(.{ 127, 0, 0, 1 }, port);
    addr.setPort(port);

    var prev_entries: []const []const u8 = &.{};
    if (args.args.entry.len != 0) {
        prev_entries = args.args.entry;
    } else {
        prev_entries = &.{ "index.html", "index.htm", "index.txt" };
    }
    const max_bytes = args.args.@"max-bytes" orelse 8192;

    var entries = try allocator.alloc([]const u8, prev_entries.len);
    for (prev_entries, 0..) |entry, i| {
        entries[i] = try allocator.dupe(u8, entry);
    }

    return .{
        .allocator = allocator,
        .dir = dir,
        .global_dir = global_dir,
        .addr = addr,
        .port_range = port_range,
        .max_bytes = max_bytes,
        .entries = entries,
    };
}

pub fn deinit(self: *Self) void {
    self.dir.close();
    self.global_dir.close();
    for (self.entries) |entry| {
        self.allocator.free(entry);
    }
    self.allocator.free(self.entries);
}

const std = @import("std");
const arg = @import("arg.zig");
const errhandl = @import("../errhandl.zig");
