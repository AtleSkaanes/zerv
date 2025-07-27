const params = clap.parseParamsComptime(
    \\-h, --help                        Display this help page and exits
    \\-v, --version                     Display this programs version and exit
    \\-d, --dir         <path>          Specify the path to the directory to serve from, defaults to ./serve/, or cwd if ./serve/ doesn't exist
    \\-g, --global      <path>          Specify the path to the directory that holds global files, like global.css, defaults to ./global/, or cwd if ./global/ doesn't exist
    \\-b, --bind        <address>       Specify the address to bind to, defaults to 127.0.0.1
    \\-r, --port-range  <range>         Specify the range of ports to try to connect to, defaults to 8000-9000
    \\-p, --port        <port>          Specify the port to use, this will make the program crash if the port is already in use
    \\-e, --entry       <str>...        Specify the entry files to look for, if no direct path is used, defaults to 'index.html'
    \\-l, --log         <loglevel>      Specify the log level (none, fatal, err, warn, info (default), verbose)
    \\--max-bytes       <bytes>         Specify the max amount of bytes allowed in incoming http requests, defaults to 8192 bytes
);

pub const ParseError = error{ParseError} || errhandl.AllocError;

pub const ArgRes = clap.Result(clap.Help, &params, parsers);

pub fn parseArgs(allocator: std.mem.Allocator) ParseError!ArgRes {
    var diag = clap.Diagnostic{};

    const args = clap.parse(clap.Help, &params, parsers, .{
        .diagnostic = &diag,
        .allocator = allocator,
        .assignment_separators = "=:",
    }) catch |err| {
        const stream = log.LogStream(.err, false);
        try diag.report(stream, err);
        return error.ParseError;
    };

    if (args.args.help >= 1) {
        clap.help(std.io.getStdOut().writer(), clap.Help, &params, .{ .spacing_between_parameters = 0 }) catch {};
        std.process.exit(0);
    }

    return args;
}

const parsers = .{
    .path = parse_dir,
    .range = parse_range,
    .port = clap.parsers.int(u16, 0),
    .address = parse_address,
    .str = clap.parsers.string,
    .bytes = clap.parsers.int(usize, 0),
    .loglevel = clap.parsers.enumeration(log.LogLevel),
};

fn parse_range(in: []const u8) !Ctx.PortRange {
    var parts = std.mem.splitScalar(u8, in, '-');

    const from_str = parts.next() orelse return error.RangeMissingFrom;
    const to_str = parts.next() orelse return error.RangeMissingTo;

    const from = std.fmt.parseInt(u16, from_str, 0) catch return error.RangeInvalidNumber;
    const to = std.fmt.parseInt(u16, to_str, 0) catch return error.RangeInvalidNumber;

    return .{ .from = from, .to = to };
}

fn parse_address(in: []const u8) !std.net.Address {
    if (std.mem.eql(u8, in, "localhost"))
        return std.net.Address.initIp4(.{ 127, 0, 0, 1 }, 8080);

    return std.net.Address.resolveIp(in, 8080);
}

fn parse_dir(in: []const u8) std.fs.File.OpenError!std.fs.Dir {
    const f = try std.fs.cwd().openDir(in, .{});
    return f;
}

const std = @import("std");
const errhandl = @import("../errhandl.zig");
const log = @import("../log.zig");
const Ctx = @import("Ctx.zig");

const clap = @import("clap");
