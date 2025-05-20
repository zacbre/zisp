pub const lexer = @import("lexer.zig");
pub const parser = @import("parser.zig");
pub const machine = @import("machine.zig");
const std = @import("std");
const testing = std.testing;

test {
    testing.refAllDecls(@This());
}
