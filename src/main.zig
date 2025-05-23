pub const root = @import("root");
pub const machine = @import("machine.zig");
const std = @import("std");
const GetBuiltIn = @import("builtin.zig").getBuiltin;
const parser = @import("parser.zig");

pub fn main() !void {
    // load any lisp from a file.
    const allocator = std.heap.page_allocator;
    const file = try std.fs.cwd().openFile("test.lisp", .{});
    defer file.close();
    const file_size = try file.getEndPos();
    const file_contents = try file.readToEndAlloc(allocator, file_size);
    defer allocator.free(file_contents);
    var interp = machine.Machine.init(file_contents, allocator);
    defer interp.deinit();
    const result = try interp.run();
    std.debug.print("Result: ", .{});
    const printfn = GetBuiltIn(.print).value.function;

    _ = try printfn(&interp, interp.context, &[_]*parser.AstNode{result});
}
