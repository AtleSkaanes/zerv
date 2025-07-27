const CLEAR: []const u8 = "\x1b[0m";
const RED: []const u8 = "\x1b[31m";
const GREEN: []const u8 = "\x1b[32m";
const YELLOW: []const u8 = "\x1b[33m";
const DIM: []const u8 = "\x1b[2m";

pub var loglevel: LogLevel = .info;

pub fn write(comptime logtype: LogType, msg: []const u8) if (logtype != .fatal) void else noreturn {
    if (loglevel.includes(logtype.toLogLevel()))
        logtype.getOutStream().writer().print(logtype.colored(false, "{s}"), .{msg}) catch {};

    if (logtype == .fatal)
        std.process.exit(1);
}

pub fn print(comptime logtype: LogType, comptime fmt: []const u8, args: anytype) if (logtype != .fatal) void else noreturn {
    if (loglevel.includes(logtype.toLogLevel()))
        logtype.getOutStream().writer().print(logtype.colored(false, fmt), args) catch {};

    if (logtype == .fatal)
        std.process.exit(1);
}

pub fn writeVerbose(comptime logtype: LogType, msg: []const u8) if (logtype != .fatal) void else noreturn {
    if (loglevel.includes(.verbose))
        logtype.getOutStream().writer().print(logtype.colored(false, "{s}"), .{msg}) catch {};

    if (logtype == .fatal)
        std.process.exit(1);
}

pub fn printVerbose(comptime logtype: LogType, comptime fmt: []const u8, args: anytype) if (logtype != .fatal) void else noreturn {
    if (loglevel.includes(.verbose))
        logtype.getOutStream().writer().print(logtype.colored(false, fmt), args) catch {};

    if (logtype == .fatal)
        std.process.exit(1);
}

pub fn LogStream(comptime logtype: LogType, is_verbose: bool) type {
    const print_func = if (is_verbose) printVerbose else print;
    const write_func = if (is_verbose) writeVerbose else write;

    const LogWriter = struct {
        const Self = @This();
        pub fn print(comptime fmt: []const u8, args: anytype) !(if (logtype != .fatal) void else noreturn) {
            print_func(logtype, fmt, args);
        }

        pub fn write(bytes: []const u8) !(if (logtype != .fatal) void else noreturn) {
            write_func(logtype, bytes);
        }
    };

    return LogWriter;
}

pub const LogLevel = enum {
    const Self = @This();

    none,
    fatal,
    err,
    warn,
    info,
    verbose,

    pub fn includes(self: Self, lvl: Self) bool {
        return @intFromEnum(self) >= @intFromEnum(lvl);
    }
};

pub const LogType = enum {
    const Self = @This();

    fatal,
    err,
    warn,
    ok,
    info,

    pub fn toLogLevel(comptime self: Self) LogLevel {
        return switch (self) {
            .fatal => .fatal,
            .err => .err,
            .warn => .warn,
            .ok => .info,
            .info => .info,
        };
    }

    pub fn getOutStream(comptime self: Self) std.fs.File {
        return switch (self) {
            .fatal, .err, .warn, .ok => std.io.getStdErr(),
            .info => std.io.getStdOut(),
        };
    }

    fn colored(comptime self: Self, comptime verbose: bool, msg: []const u8) []const u8 {
        // Set to dim if this is a verbose message
        const style = if (verbose) DIM else "";

        const prefix = comptime switch (self) {
            .fatal => style ++ RED ++ "[fatal]: ",
            .err => style ++ RED ++ "[err]: ",
            .warn => style ++ YELLOW ++ "[warning]: ",
            .ok => style ++ GREEN ++ "[ok]: ",
            .info => "[info]: ",
        };

        return prefix ++ msg ++ CLEAR;
    }
};

const std = @import("std");
