pub const File = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    name: []const u8,
    mimetype: []const u8,
    file: std.fs.File,

    pub fn deinit(self: Self) void {
        self.allocator.free(self.name);
        self.allocator.free(self.mimetype);
        self.file.close();
    }
};

pub fn getFile(allocator: std.mem.Allocator, ctx: *const Ctx, path: []const u8) (error{FileNotFound} || errhandl.AllocError)!File {
    if (ctx.dir.openDir(path, .{})) |subdir| {
        for (ctx.entries) |entry| {
            const f = subdir.openFile(entry, .{}) catch continue;
            const f_name = basename(entry);
            return .{
                .allocator = allocator,
                .name = try allocator.dupe(u8, f_name),
                .mimetype = try getMimeType(allocator, f_name),
                .file = f,
            };
        }
    } else |_| {}

    if (ctx.dir.openFile(path, .{})) |f| {
        const f_name = basename(path);
        return .{
            .allocator = allocator,
            .name = try allocator.dupe(u8, f_name),
            .mimetype = try getMimeType(allocator, f_name),
            .file = f,
        };
    } else |_| {}

    // look for files that have the basename specified in path, so match "index" to "index.html"
    const f_name = basename(path);
    const new_path = popPath(path) orelse ".";

    if (ctx.dir.openDir(new_path, .{ .iterate = true })) |dir| {
        var walker = try dir.walk(allocator);
        defer walker.deinit();

        while (walker.next() catch null) |entry| {
            if (entry.kind == .directory)
                continue;

            const name = popFileExt(entry.basename);

            // ignore dotfiles here
            if (name.len == 0)
                continue;

            if (std.mem.eql(u8, name, f_name)) {
                const f = dir.openFile(entry.basename, .{}) catch return error.FileNotFound;
                return .{
                    .allocator = allocator,
                    .name = try allocator.dupe(u8, entry.basename),
                    .mimetype = try getMimeType(allocator, entry.basename),
                    .file = f,
                };
            }
        }
    } else |_| {}

    return error.FileNotFound;
}

pub fn normalizePath(allocator: std.mem.Allocator, path: []const u8) (error{InvalidPath} || errhandl.AllocError)![]u8 {
    var path_builder = std.ArrayList([]const u8).init(allocator);
    defer {
        for (path_builder.items) |part| {
            allocator.free(part);
        }
        path_builder.deinit();
    }

    var parts = std.mem.splitAny(u8, path, "/\\");

    while (parts.next()) |part| {
        const lower_buffer = try allocator.alloc(u8, part.len);
        const lower_part = std.ascii.lowerString(lower_buffer, part);

        if (lower_part.len == 0 or std.mem.eql(u8, lower_part, "."))
            continue;

        if (std.mem.eql(u8, lower_part, "..")) {
            if (path_builder.pop()) |old_part| {
                allocator.free(old_part);
            }
            continue;
        }

        try path_builder.append(try allocator.dupe(u8, lower_part));
    }

    if (path_builder.items.len == 0)
        return try allocator.dupe(u8, ".");

    // if (path_builder.items.len == 1) {
    //     std.debug.print("PATH ITEM: '{s}', with align: {}\n", .{ path_builder.items[0], @alignOf(@TypeOf(path_builder.items)) });
    //     return try allocator.dupe(u8, path_builder.items[0]);
    // }

    return try std.mem.join(allocator, "/", path_builder.items);
}

pub fn popPath(path: []const u8) ?[]const u8 {
    var parts = std.mem.splitBackwardsAny(u8, path, "/\\");
    _ = parts.next();

    if (parts.rest().len == 0)
        return null;

    return parts.rest();
}

pub fn basename(path: []const u8) []const u8 {
    var parts = std.mem.splitBackwardsAny(u8, path, "/\\");
    return parts.first();
}

pub fn popFileExt(path: []const u8) []const u8 {
    var parts = std.mem.splitBackwardsAny(u8, path, ".");
    _ = parts.next();
    return parts.rest();
}

pub fn getMimeType(allocator: std.mem.Allocator, filename: []const u8) errhandl.AllocError![]const u8 {
    var parts = std.mem.splitScalar(u8, filename, '.');
    _ = parts.next();
    const ext = parts.next() orelse "";

    if (std.mem.eql(u8, ext, "html") or std.mem.eql(u8, ext, "htm"))
        return try allocator.dupe(u8, "text/html");

    if (std.mem.eql(u8, ext, "css"))
        return try allocator.dupe(u8, "text/css");

    if (std.mem.eql(u8, ext, "js"))
        return try allocator.dupe(u8, "application/javascript");

    if (std.mem.eql(u8, ext, "txt"))
        return try allocator.dupe(u8, "text/plain");

    if (std.mem.eql(u8, ext, "pdf"))
        return try allocator.dupe(u8, "application/pdf");

    if (std.mem.eql(u8, ext, "csv"))
        return try allocator.dupe(u8, "text/csv");

    if (std.mem.eql(u8, ext, "jpeg") or std.mem.eql(u8, ext, "jpg"))
        return try allocator.dupe(u8, "image/jpeg");

    if (std.mem.eql(u8, ext, "png"))
        return try allocator.dupe(u8, "image/png");

    if (std.mem.eql(u8, ext, "mp4"))
        return try allocator.dupe(u8, "video/mp4");

    if (std.mem.eql(u8, ext, "mp3"))
        return try allocator.dupe(u8, "video/mpeg");

    return try allocator.dupe(u8, "application/octet-stream");
}

const std = @import("std");
const errhandl = @import("errhandl.zig");
const Ctx = @import("./ctx/Ctx.zig");
