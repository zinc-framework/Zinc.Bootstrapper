const std = @import("std");
const file_reader = @import("file_reader");

pub const sharedString = blk: {
    const result = file_reader.readFileToString("example.txt") catch |err| {
        @compileError("Failed to read file at compile time: {err}");
    };
    break :blk result;
};
