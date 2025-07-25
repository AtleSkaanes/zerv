pub const AllocError = std.mem.Allocator.Error;

/// Panic if errunion is a Allocator.Error
pub fn tryAlloc(T: type, alloc: AllocError!T) T {
    return alloc catch {
        log.write(.fatal, "Ran out of heap memory");
    };
}

const std = @import("std");
const log = @import("log.zig");
