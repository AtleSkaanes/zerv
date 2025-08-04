/// 1 GB
const max_read_bytes = 1_000_000_000;

pub const Preproc = enum {
    c,
    m4,
    smed,
    none,
};

pub const PreprocCmd = struct {
    c: []const []const u8,
    m4: []const []const u8,
    smed: ?[]const []const u8,
};

pub fn preprocess(allocator: std.mem.Allocator, ctx: *const Ctx, conn: *const std.net.Server.Connection, req: *const HttpData, file: fs.File) ![]u8 {
    const preproc: Preproc = if (std.mem.eql(u8, file.mimetype, "text/html")) ctx.preproc else .none;

    const dir = if (file.is_global) ctx.global_dir else ctx.dir;
    const real_path = try dir.realpathAlloc(allocator, file.path);

    var info = try Info.init(allocator, ctx, conn, req, file.path);
    defer info.deinit(allocator);

    const preproc_args = switch (preproc) {
        .c => c_args: {
            const info_args = try info.toCppArgs(allocator);
            defer freeNested(allocator, info_args);

            break :c_args try concatArgs(allocator, ctx.preproc_cmd.c, info_args);
        },
        .m4 => m4_args: {
            const info_args = try info.toCppArgs(allocator);
            defer freeNested(allocator, info_args);

            break :m4_args try concatArgs(allocator, ctx.preproc_cmd.m4, info_args);
        },
        .smed => {
            var smed = try libsmed.Smed.init(allocator);
            defer smed.deinit();

            try info.injectToSmed(&smed);

            const content = try file.file.readToEndAlloc(ctx.allocator, max_read_bytes);
            defer allocator.free(content);

            const out = try smed.evalStr(content);
            return out;
        },
        .none => {
            return try file.file.readToEndAlloc(ctx.allocator, max_read_bytes);
        },
    };
    defer freeNested(allocator, preproc_args);

    var args = try std.ArrayList([]const u8).initCapacity(
        allocator,
        preproc_args.len + file.path.len,
    );
    defer args.deinit();
    try args.appendSlice(preproc_args);
    try args.append(real_path);

    const res = std.process.Child.run(.{ .allocator = allocator, .argv = args.items }) catch |err| {
        const command = try std.mem.join(allocator, " ", args.items);
        defer allocator.free(command);
        log.print(.err, "Failed to run command '{s}', because of {}\n", .{ command, err });
        return error.CmdRunError;
    };

    defer allocator.free(res.stderr);
    defer allocator.free(res.stdout);

    const command = try std.mem.join(allocator, " ", args.items);
    defer allocator.free(command);
    log.printVerbose(.ok, "Succesfully ran command '{s}'\n", .{command});

    // TODO: Check for exit codes

    return try allocator.dupe(u8, res.stdout);
}

const Info = struct {
    const Self = @This();

    const KeyValEntry = struct { key: []const u8, val: []const u8 };

    conn: struct {
        client_ip: []const u8,
        client_port: u16,
        server_ip: []const u8,
        server_port: u16,
    },
    request: struct {
        queryparams: []const KeyValEntry,
        raw_queryparams: []const u8,
        headers: []const KeyValEntry,
        raw_headers: []const u8,
        path: []const u8,
        full_req: []const u8,
        method: []const u8,
        body: []const u8,
    },
    paths: struct {
        serve_dir: []const u8,
        global_dir: []const u8,
        current_file: []const u8,
    },

    const InitError = error{
        InvalidCLientAddress,
        InvalidDir,
    } || errhandl.AllocError;

    pub fn init(allocator: std.mem.Allocator, ctx: *const Ctx, conn: *const std.net.Server.Connection, req: *const HttpData, path: []const u8) InitError!Self {
        const client_addr = try std.fmt.allocPrint(allocator, "{}", .{conn.address});
        defer allocator.free(client_addr);
        var client_ip = std.mem.splitScalar(u8, client_addr, ':');

        const server_addr = try std.fmt.allocPrint(allocator, "{}", .{ctx.addr});
        defer allocator.free(server_addr);
        var server_ip = std.mem.splitScalar(u8, server_addr, ':');

        var queryparams = std.ArrayList(KeyValEntry).init(allocator);
        defer queryparams.deinit();
        var query_iter = req.queryparams.iterator();

        while (query_iter.next()) |param| {
            try queryparams.append(.{
                .key = try allocator.dupe(u8, param.key_ptr.*),
                .val = try allocator.dupe(u8, param.value_ptr.*),
            });
        }

        const raw_queryparams = if (req.raw_queryparams) |q| try allocator.dupe(u8, q) else null;

        var headers = std.ArrayList(KeyValEntry).init(allocator);
        defer headers.deinit();
        var header_iter = req.headers.iterator();

        while (header_iter.next()) |header| {
            try headers.append(.{
                .key = try allocator.dupe(u8, header.key_ptr.*),
                .val = try allocator.dupe(u8, header.value_ptr.*),
            });
        }

        return Self{
            .conn = .{
                .client_ip = try allocator.dupe(u8, client_ip.first()),
                .client_port = conn.address.getPort(),
                .server_ip = try allocator.dupe(u8, server_ip.first()),
                .server_port = ctx.addr.getPort(),
            },
            .request = .{
                .queryparams = try queryparams.toOwnedSlice(),
                .raw_queryparams = raw_queryparams,
                .headers = try headers.toOwnedSlice(),
                .raw_headers = try allocator.dupe(u8, req.raw_headers),
                .path = try allocator.dupe(u8, req.path),
                .full_req = try allocator.dupe(u8, req.raw_req),
                .method = try allocator.dupe(u8, @tagName(req.method)),
                .body = try allocator.dupe(u8, req.body),
            },
            .paths = .{
                .serve_dir = ctx.dir.realpathAlloc(allocator, ".") catch return error.InvalidDir,
                .global_dir = ctx.global_dir.realpathAlloc(allocator, ".") catch return error.InvalidDir,
                .current_file = try allocator.dupe(u8, path),
            },
        };
    }

    pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
        allocator.free(self.conn.client_ip);
        allocator.free(self.conn.server_ip);

        allocator.free(self.request.raw_queryparams);
        allocator.free(self.request.raw_headers);
        allocator.free(self.request.path);
        allocator.free(self.request.full_req);
        allocator.free(self.request.method);
        allocator.free(self.request.body);

        allocator.free(self.paths.serve_dir);
        allocator.free(self.paths.global_dir);
        allocator.free(self.paths.current_file);

        for (self.request.queryparams) |param| {
            allocator.free(param.key);
            allocator.free(param.val);
        }

        for (self.request.headers) |header| {
            allocator.free(header.key);
            allocator.free(header.val);
        }
    }

    pub fn injectToSmed(self: Self, smed: *libsmed.Smed) !void {
        try smed.addGlobal(self, "info");

        const transform_code: [:0]const u8 = @embedFile("./lua/transform_info.luau");

        try smed.runRawLuauStr(transform_code);
    }

    pub fn toCppArgs(self: Self, allocator: std.mem.Allocator) errhandl.AllocError![][]const u8 {
        var arg_builder = std.ArrayList([]const u8).init(allocator);
        defer arg_builder.deinit();

        const print = std.fmt.allocPrint;

        var arena = std.heap.ArenaAllocator.init(allocator);
        defer {
            _ = arena.reset(.free_all);
            arena.deinit();
        }

        const a = arena.allocator();

        try arg_builder.append(try print(allocator, "-DINFO_CONN_CLIENT_IP={s}", .{try fixCppValue(a, self.conn.client_ip)}));
        try arg_builder.append(try print(allocator, "-DINFO_CONN_CLIENT_PORT={}", .{self.conn.client_port}));
        try arg_builder.append(try print(allocator, "-DINFO_CONN_SERVER_IP={s}", .{try fixCppValue(a, self.conn.server_ip)}));
        try arg_builder.append(try print(allocator, "-DINFO_CONN_SERVER_PORT={}", .{self.conn.server_port}));
        try arg_builder.append(try print(allocator, "-DINFO_REQUEST_RAW_QUERYPARAMS=\"{s}\"", .{try fixCppValue(a, self.request.raw_queryparams)}));
        try arg_builder.append(try print(allocator, "-DINFO_REQUEST_RAW_HEADERS=\"{s}\"", .{try fixCppValue(a, self.request.raw_headers)}));
        try arg_builder.append(try print(allocator, "-DINFO_REQUEST_PATH=\"{s}\"", .{try fixCppValue(a, self.request.path)}));
        try arg_builder.append(try print(allocator, "-DINFO_REQUEST_FULL_REQ=\"{s}\"", .{try fixCppValue(a, self.request.full_req)}));
        try arg_builder.append(try print(allocator, "-DINFO_REQUEST_METHOD=\"{s}\"", .{try fixCppValue(a, self.request.method)}));
        try arg_builder.append(try print(allocator, "-DINFO_REQUEST_BODY=\"{s}\"", .{try fixCppValue(a, self.request.body)}));
        try arg_builder.append(try print(allocator, "-DINFO_PATHS_SERVE_DIR=\"{s}\"", .{try fixCppValue(a, self.paths.serve_dir)}));
        try arg_builder.append(try print(allocator, "-DINFO_PATHS_GLOBAL_DIR=\"{s}\"", .{try fixCppValue(a, self.paths.global_dir)}));
        try arg_builder.append(try print(allocator, "-DINFO_PATHS_CURRENT_FILE=\"{s}\"", .{try fixCppValue(a, self.paths.current_file)}));

        // TODO: Fix identifiers:
        // - Make illigal identifiers legal. E.g. ' ' => '_'
        // - Make identifiers screaming snake case to fit style
        // Applies to both queryparams and headers
        for (self.request.queryparams) |param| {
            try arg_builder.append(try print(allocator, "-DINFO_REQUEST_QUERYPARAM_{s}={s}", .{ param.key, param.val }));
        }
        for (self.request.headers) |header| {
            try arg_builder.append(try print(allocator, "-DINFO_REQUEST_HEADER_{s}={s}", .{ header.key, header.val }));
        }

        return try arg_builder.toOwnedSlice();
    }
};

fn concatArgs(allocator: std.mem.Allocator, rhs: []const []const u8, lhs: []const []const u8) errhandl.AllocError![][]const u8 {
    var arg_builder = try std.ArrayList([]const u8).initCapacity(allocator, rhs.len + lhs.len);
    defer arg_builder.deinit();

    for (rhs) |arg| {
        try arg_builder.append(try allocator.dupe(u8, arg));
    }
    for (lhs) |arg| {
        try arg_builder.append(try allocator.dupe(u8, arg));
    }

    return try arg_builder.toOwnedSlice();
}

fn freeNested(allocator: std.mem.Allocator, slices: []const []const u8) void {
    for (slices) |slice| {
        allocator.free(slice);
    }
    allocator.free(slices);
}

fn fixCppValue(allocator: std.mem.Allocator, str: []const u8) errhandl.AllocError![]u8 {
    return try std.mem.replaceOwned(u8, allocator, str, "\r\n", "<br>");
}

const std = @import("std");
const log = @import("log.zig");
const fs = @import("fs.zig");
const errhandl = @import("errhandl.zig");
const Ctx = @import("ctx/Ctx.zig");
const HttpData = @import("http/HttpData.zig");

const libsmed = @import("libsmed");
