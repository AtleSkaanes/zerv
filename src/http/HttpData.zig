const Self = @This();

pub const ProtocolType = enum { http, https };

pub const Protocol = struct {
    protocol: ProtocolType,
    version: f32,

    pub fn fromStr(str: []const u8) error{InvalidProtocol}!Protocol {
        var parts = std.mem.splitScalar(u8, str, '/');
        const prot_str = parts.next() orelse return error.InvalidProtocol;
        if (prot_str.len > 5)
            return error.InvalidProtocol;

        var buf: [5]u8 = undefined;
        const lowered_str = std.ascii.lowerString(&buf, trim(prot_str));
        const protocol: ProtocolType = if (std.mem.eql(u8, lowered_str, "http")) .http else if (std.mem.eql(u8, lowered_str, "https")) .https else {
            return error.InvalidProtocol;
        };

        const version_str = parts.next() orelse return error.InvalidProtocol;
        const version = std.fmt.parseFloat(f32, version_str) catch return error.InvalidProtocol;

        return .{
            .protocol = protocol,
            .version = version,
        };
    }
};

pub const Method = enum {
    get,
    head,
    post,
    put,
    delete,
    connect,
    options,
    trace,
    path,

    pub fn fromStr(str: []const u8) error{InvalidMethod}!Method {
        if (str.len >= 10)
            return error.InvalidMethod;

        var buf: [10]u8 = undefined;

        const lowered_str = std.ascii.lowerString(&buf, trim(str));

        const fields = std.meta.fieldNames(Method);
        for (fields, 0..) |field, i| {
            if (std.mem.eql(u8, field, lowered_str))
                return @enumFromInt(i);
        }
        return error.InvalidMethod;
    }
};

allocator: std.mem.Allocator,
method: Method,
path: []const u8,
queryparams: std.StringHashMap([]const u8),
raw_queryparams: ?[]const u8,
protocol: Protocol,
headers: std.StringHashMap([]const u8),
raw_headers: []const u8,
body: []const u8,
raw_req: []const u8,

pub const ParseError = error{
    InvalidPart,
    InvalidProtocol,
    InvalidMethod,
    InvalidPath,
    InvalidHeader,
    InvalidQueryParam,
} || errhandl.AllocError;

pub fn parse(allocator: std.mem.Allocator, str: []const u8) ParseError!Self {
    if (str.len == 0)
        return error.InvalidPart;

    var lines = std.mem.splitScalar(u8, str, '\n');

    const first = lines.next() orelse return error.InvalidPart;
    var first_parts = std.mem.splitScalar(u8, trim(first), ' ');

    const method_str = first_parts.next() orelse return error.InvalidPart;
    const method = try Method.fromStr(method_str);

    const access_str = first_parts.next() orelse return error.InvalidPart;

    const decoded_str = try urlDecodeAlloc(allocator, access_str);
    defer allocator.free(decoded_str);

    var access_parts = std.mem.splitScalar(u8, decoded_str, '?');
    const path_str = access_parts.first();
    const path = try fs.normalizePath(allocator, path_str);

    const raw_queryparams = if (access_parts.next()) |q| try allocator.dupe(u8, q) else null;

    var queryparams = std.StringHashMap([]const u8).init(allocator);
    if (raw_queryparams) |query| {
        try parseQueryParams(&queryparams, query);
    }

    const protocol_str = first_parts.next() orelse return error.InvalidPart;
    const protocol = try Protocol.fromStr(protocol_str);

    var headers = std.StringHashMap([]const u8).init(allocator);
    var raw_headers = std.ArrayList([]const u8).init(allocator);
    defer raw_headers.deinit();

    while (lines.next()) |line| {
        const line_str = trim(line);
        if (line_str.len == 0)
            break;

        try raw_headers.append(try allocator.dupe(u8, line_str));

        var parts = std.mem.splitScalar(u8, line_str, ':');
        const key = parts.next() orelse return error.InvalidHeader;
        const value = parts.next() orelse return error.InvalidHeader;

        try headers.put(try allocator.dupe(u8, trim(key)), try allocator.dupe(u8, trim(value)));
    }

    const body = lines.rest();

    return .{
        .allocator = allocator,
        .method = method,
        .path = path,
        .queryparams = queryparams,
        .raw_queryparams = raw_queryparams,
        .protocol = protocol,
        .headers = headers,
        .raw_headers = try std.mem.join(allocator, "\n", raw_headers.items),
        .body = body,
        .raw_req = try allocator.dupe(u8, str),
    };
}

fn parseQueryParams(querymap: *std.StringHashMap([]const u8), str: []const u8) (error{InvalidQueryParam} || errhandl.AllocError)!void {
    // TODO: Parse query params
    _ = querymap;
    _ = str;
}

pub fn urlEncodeAlloc(allocator: std.mem.Allocator, str: []const u8) (error{InvalidQueryParam} || errhandl.AllocError)![]u8 {
    var sb = std.ArrayList(u8).init(allocator);
    defer sb.deinit();

    for (str) |ch| {
        switch (ch) {
            'A'...'Z', 'a'...'z', '0'...'9', '-', '_', '.', '~' => try sb.append(ch),
            _ => {
                var buf: [3]u8 = undefined;
                const encoded = std.fmt.bufPrint(&buf, "%{X}", .{ch}) catch return error.InvalidQueryParam;
                try sb.appendSlice(encoded);
            },
        }
    }
}

pub fn urlDecodeAlloc(allocator: std.mem.Allocator, str: []const u8) (error{InvalidQueryParam} || errhandl.AllocError)![]u8 {
    var sb = std.ArrayList(u8).init(allocator);
    defer sb.deinit();

    var i: usize = 0;
    while (i < str.len) {
        if (str[i] == '%') {
            if (i + 2 >= str.len)
                return error.InvalidQueryParam;

            const byte = std.fmt.parseInt(u8, &.{ str[i + 1], str[i + 2] }, 16) catch return error.InvalidQueryParam;
            try sb.append(byte);
            i += 2;
        } else {
            try sb.append(str[i]);
            i += 1;
        }
    }

    return sb.toOwnedSlice();
}

fn trim(str: []const u8) []const u8 {
    return std.mem.trim(u8, str, " \r\n");
}

pub fn freeHashMap(allocator: std.mem.Allocator, map: *std.StringHashMap([]const u8)) void {
    var key_iter = map.keyIterator();
    while (key_iter.next()) |key| {
        allocator.free(key.*);
    }
    var value_iter = map.valueIterator();
    while (value_iter.next()) |val| {
        allocator.free(val.*);
    }
    map.deinit();
}

pub fn deinit(self: *Self) void {
    freeHashMap(self.allocator, &self.headers);
    freeHashMap(self.allocator, &self.queryparams);

    self.allocator.free(self.path);
    self.allocator.free(self.body);
    self.allocator.free(self.raw_req);
}

const std = @import("std");
const errhandl = @import("../errhandl.zig");
const log = @import("../log.zig");
const fs = @import("../fs.zig");
