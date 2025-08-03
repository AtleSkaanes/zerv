const Self = @This();
pub const PortRange = struct { from: u16, to: u16 };

allocator: std.mem.Allocator,

dir: std.fs.Dir,
global_dir: std.fs.Dir,
addr: std.net.Address,
port_range: ?PortRange,
max_bytes: usize,
entries: []const []const u8,
preproc: prep.Preproc,
preproc_cmd: prep.PreprocCmd,

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

    const preproc: prep.Preproc = args.args.preproc orelse .none;

    const c_cmd_prev: []const []const u8 = if (args.args.@"c-preproc-cmd".len != 0) args.args.@"c-preproc-cmd" else &.{ "cpp", "-P" };
    const m4_cmd_prev: []const []const u8 = if (args.args.@"m4-preproc-cmd".len != 0) args.args.@"m4-preproc-cmd" else &.{"m4"};
    const smed_cmd_prev: ?[]const []const u8 = if (args.args.@"smed-preproc-cmd".len != 0) args.args.@"smed-preproc-cmd" else null;

    // Make the preproc cmds be on the heap
    const c_cmd = try allocator.alloc([]const u8, c_cmd_prev.len);
    const m4_cmd = try allocator.alloc([]const u8, m4_cmd_prev.len);
    const smed_cmd = if (smed_cmd_prev) |smed| try allocator.alloc([]const u8, smed.len) else null;

    for (c_cmd_prev, 0..) |cmd, i| {
        c_cmd[i] = try allocator.dupe(u8, cmd);
    }
    for (m4_cmd_prev, 0..) |cmd, i| {
        m4_cmd[i] = try allocator.dupe(u8, cmd);
    }
    if (smed_cmd_prev) |smed| {
        for (smed, 0..) |cmd, i| {
            smed_cmd.?[i] = try allocator.dupe(u8, cmd);
        }
    }

    return .{
        .allocator = allocator,
        .dir = dir,
        .global_dir = global_dir,
        .addr = addr,
        .port_range = port_range,
        .max_bytes = max_bytes,
        .entries = entries,
        .preproc = preproc,
        .preproc_cmd = .{
            .c = c_cmd,
            .m4 = m4_cmd,
            .smed = smed_cmd,
        },
    };
}

pub fn deinit(self: *Self) void {
    self.dir.close();
    self.global_dir.close();

    for (self.entries) |entry| {
        self.allocator.free(entry);
    }
    self.allocator.free(self.entries);

    for (self.preproc_cmd.c) |cmd| {
        self.allocator.free(cmd);
    }
    self.allocator.free(self.preproc_cmd.c);

    for (self.preproc_cmd.m4) |cmd| {
        self.allocator.free(cmd);
    }
    self.allocator.free(self.preproc_cmd.m4);

    if (self.preproc_cmd.smed) |smed| {
        for (smed) |cmd| {
            self.allocator.free(cmd);
        }
        self.allocator.free(smed);
    }
}

const std = @import("std");
const arg = @import("arg.zig");
const errhandl = @import("../errhandl.zig");
const prep = @import("../prep.zig");
