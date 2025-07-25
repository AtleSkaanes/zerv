pub fn start(ctx: *Ctx) !void {
    var server: std.net.Server = addr: {
        if (ctx.port_range) |range| {
            for (range.from..range.to) |port| {
                ctx.addr.setPort(@intCast(port));
                const server = ctx.addr.listen(.{}) catch continue;
                break :addr server;
            }
            log.print(.fatal, "All ports in range {}-{} are already bound\n", .{ range.from, range.to });
        } else {
            break :addr ctx.addr.listen(.{}) catch {
                log.print(.fatal, "Port {} is already bound\n", .{ctx.addr.getPort()});
            };
        }
        ctx.addr.listen(.{});
    };
    defer server.stream.close();

    log.print(.ok, "Server started listening at \x1b[33mhttp://{}\n", .{server.listen_address});

    while (true) {
        const conn = server.accept() catch {
            continue;
        };
        const accepted_at = std.time.milliTimestamp();

        log.print(.ok, "Accepted client at {}\n", .{conn.address});

        var buf = try ctx.allocator.alloc(u8, ctx.max_bytes + 1);
        defer ctx.allocator.free(buf);

        const bytes = try conn.stream.reader().read(buf);

        if (bytes == ctx.max_bytes + 1) {
            log.print(.warn, "Got HTTP request with URI Too Long from '{}'", .{conn.address});
            try serve414(&conn);
            continue;
        }
        if (bytes == 0) {
            log.write(.warn, "Got empty HTTP request");
            continue;
        }

        log.printVerbose(.info, "Got request:\n======\n{s}\n======\n", .{buf[0..bytes]});

        var data = HttpData.parse(ctx.allocator, buf[0..bytes]) catch |err| {
            log.print(.err, "failed to parse HTTP header: {any}", .{err});
            continue;
        };
        defer data.deinit();

        log.printVerbose(.ok, "Recieved {} bytes from {}\n", .{ bytes, conn.address });

        serveFile(ctx, &data, &conn) catch |err| log.print(.err, "Error while serving to {}: {any}\n", .{ conn.address, err });

        const time_taken = std.time.milliTimestamp() - accepted_at;
        log.print(.ok, "Served file in {} ms\n", .{time_taken});

        conn.stream.close();
    }
}

fn serveFile(ctx: *const Ctx, request: *const HttpData, conn: *const std.net.Server.Connection) !void {
    const file = fs.getFile(ctx.allocator, ctx, request.path) catch {
        try serve404(ctx, conn);
        return error.FileNotFound;
    };
    defer file.deinit();

    const content = try file.file.readToEndAlloc(ctx.allocator, 10_000_000_000);

    const response = try createHttpResponse(ctx.allocator, file.mimetype, content);
    defer ctx.allocator.free(response);

    const bytes = try conn.stream.write(response);
    log.printVerbose(.ok, "Sent a {} byte response to {}\n", .{ bytes, conn.address });
}

fn serve404(ctx: *const Ctx, conn: *const std.net.Server.Connection) !void {
    const body =
        \\<!DOCTYPE html>
        \\<html>
        \\<head>
        \\<title>404</title>
        \\</head>
        \\<body>
        \\<hr>
        \\404 - Not found
        \\<hr>
        \\<p>The site was not found, sorry :/</p>
        \\</body>
        \\</html>
    ;

    const response = try createHttpResponse(ctx.allocator, "text/html", body);

    const bytes = try conn.stream.write(response);
    log.printVerbose(.ok, "Sent a {} byte response to {}\n", .{ bytes, conn.address });
}

fn serve414(conn: *const std.net.Server.Connection) !void {
    const response =
        \\HTTP/1.1 414 URI Too Long
    ;

    const bytes = try conn.stream.write(response);
    log.printVerbose(.ok, "Sent a {} byte response to {}\n", .{ bytes, conn.address });
}

fn createHttpResponse(allocator: std.mem.Allocator, mimetype: []const u8, body: []const u8) errhandl.AllocError![]u8 {
    return std.fmt.allocPrint(allocator,
        \\HTTP/1.1 200 OK
        \\Content-Type: {s}
        \\Content-Length: {}
        \\
        \\{s}
    , .{ mimetype, body.len, body });
}

const std = @import("std");
const log = @import("log.zig");
const errhandl = @import("errhandl.zig");
const fs = @import("fs.zig");
const HttpData = @import("http/HttpData.zig");
const Ctx = @import("ctx/Ctx.zig");
