const std = @import("std");

pub fn readFileToString(comptime file_path: []const u8) ![]const u8 {
    const file = try std.fs.cwd().openFile(file_path, .{ .read = true });
    defer file.close();

    const allocator = std.heap.page_allocator;
    const buffer = try file.readAllAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(buffer);

    return buffer;
}
