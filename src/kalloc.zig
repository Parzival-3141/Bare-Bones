//! *Very* basic bitmap allocator. Backed with statically allocated memory.

const std = @import("std");
const Allocator = std.mem.Allocator;

const pool_size = 1024 * 1024; // 1MiB
const chunk_size = 8; // 8bytes

var backing_mem: [pool_size]u8 linksection(".bss") = undefined;
var bitmap: [pool_size / chunk_size]u1 linksection(".bss") = undefined;

pub fn init() void {
    @memset(&bitmap, 0);
}

pub fn allocator() Allocator {
    return .{
        .ptr = undefined,
        .vtable = &.{
            .alloc = alloc,
            .resize = Allocator.noResize,
            .free = free,
        },
    };
}

fn alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
    _ = ptr_align;
    _ = ret_addr;
    _ = ctx;

    if (len == 0) return null;
    // const alignment = @as(usize, 1) << ptr_align;

    asm volatile ("xchgw %bx, %bx"); // bochs breakpoint

    // @Todo: this doesn't account for pointer alignment.
    const num_chunks = std.math.divCeil(usize, len, chunk_size) catch unreachable;
    const starting_chunk = contiguous_search(num_chunks) orelse return null;

    @memset(bitmap[starting_chunk..][0..num_chunks], 1);

    return @ptrCast(&backing_mem[starting_chunk * chunk_size]);
}

fn free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
    _ = ret_addr;
    _ = buf_align;
    _ = ctx;

    const byte_offset = @intFromPtr(buf.ptr) - @intFromPtr(&backing_mem);
    const starting_chunk = byte_offset / chunk_size;
    const len = buf.len / chunk_size;

    @memset(bitmap[starting_chunk..][0..len], 0);
}

/// Search for `len` contiguous chunks, returning the starting chunk index if
/// found, else null.
fn contiguous_search(len: usize) ?usize {
    if (len > bitmap.len) return null;

    var idx: usize = 0;
    var count: usize = 0;

    const found = while (idx < bitmap.len) : (idx += 1) {
        // search for free chunk
        if (bitmap[idx] == 1) {
            count = 0;
            continue;
        }

        // search for block of 'len' free chunks
        count += 1;
        if (count == len) {
            // move back to start of block since we're reusing `idx`.
            idx -= count - 1;
            break true;
        }
    } else false;

    return if (found) idx else null;
}

test "small allocations - free in same order" {
    // init();
    const ally = allocator();

    var list = std.ArrayList(*u64).init(std.testing.allocator);
    defer list.deinit();

    var i: usize = 0;
    while (i < 513) : (i += 1) {
        const ptr = try ally.create(u64);
        try list.append(ptr);
    }

    for (list.items) |ptr| {
        ally.destroy(ptr);
    }
}

test "small allocations - free in reverse order" {
    // init();
    const ally = allocator();

    var list = std.ArrayList(*u64).init(std.testing.allocator);
    defer list.deinit();

    var i: usize = 0;
    while (i < 513) : (i += 1) {
        const ptr = try ally.create(u64);
        try list.append(ptr);
    }

    while (list.popOrNull()) |ptr| {
        ally.destroy(ptr);
    }
}

// test "shrink" {
//     init();
//     const ally = allocator();

//     var slice = try ally.alloc(u8, 20);
//     defer ally.free(slice);

//     @memset(slice, 0x11);

//     try std.testing.expect(ally.resize(slice, 17));
//     slice = slice[0..17];

//     for (slice) |b| {
//         try std.testing.expect(b == 0x11);
//     }

//     try std.testing.expect(ally.resize(slice, 16));
//     slice = slice[0..16];

//     for (slice) |b| {
//         try std.testing.expect(b == 0x11);
//     }
// }

test "std test" {
    // init();
    try std.heap.testAllocator(allocator());
}
