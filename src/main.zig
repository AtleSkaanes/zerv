pub fn main() !void {
    const allocator = std.heap.smp_allocator;
    const args = arg.parseArgs(allocator) catch {
        log.write(.fatal, "Failed to parse arguments\n");
    };

    // TODO: APPLY CONFIG OPTIONS HERE

    if (args.args.log) |loglvl|
        log.loglevel = loglvl;

    var ctx = errhandl.tryAlloc(Ctx, .fromArgs(allocator, args));
    defer ctx.deinit();

    args.deinit();

    try server.start(&ctx);
}

const std = @import("std");
const arg = @import("ctx/arg.zig");
const errhandl = @import("errhandl.zig");
const log = @import("log.zig");
const server = @import("server.zig");
const Ctx = @import("ctx/Ctx.zig");
