const parser = @import("parser.zig");
const std = @import("std");
const testing = std.testing;

const builtins = @import("builtins.zig");
const builtin = @import("builtin.zig");

pub const Machine = struct {
    allocator: std.mem.Allocator,
    parser: parser.Parser,
    // todo: add scoped variables, function labels, etc

    pub fn init(input: []const u8, allocator: std.mem.Allocator) Machine {
        return Machine{
            .allocator = allocator,
            .parser = parser.Parser.init(input, allocator),
        };
    }

    pub fn eval(self: *Machine, ast: parser.AstNode) !parser.AstNode {
        switch (ast) {
            .List => |list| {
                if (list.items.len == 0) {
                    return ast;
                }
                const first = list.items[0];
                switch (first) {
                    .Symbol => |symbol| {
                        const e = std.meta.stringToEnum(builtin.Builtin, symbol);
                        if (e == null) {
                            std.debug.panic("Unknown builtin function:", .{});
                        }

                        const builtin_fn = builtin.getBuiltin(e.?).*.Function;
                        const result = builtin_fn(self, list.items[1..]) catch |err| {
                            std.debug.panic("Builtin error: {}", .{err});
                        };
                        return result;
                    },
                    // .Symbol => |symbol| {
                    //     self.math(list) catch |err| {
                    //         std.debug.panic("Math error: {}", .{err});
                    //     };
                    // },
                    else => {},
                }
            },
            .Number => |_| {
                return ast;
            },
            else => {},
        }
        return ast;
    }

    pub fn run(self: *Machine) !void {
        const ast = self.parser.parse_expression();
        defer ast.deinit(self.allocator);
    }
};

test "evaluate simple addition" {
    const input = "(+ 2 5)";
    var allocator = std.testing.allocator;
    var machine = Machine.init(input, allocator);

    const ast = try machine.parser.parse();
    defer ast.deinit(&allocator);

    const result = machine.eval(ast) catch @panic("Eval failed");
    defer result.deinit(&allocator);

    try testing.expect(result == .Number);
    try testing.expect(result.Number == 7);
}

test "evaluate simple subtraction" {
    const input = "(- 5 2)";
    var allocator = std.testing.allocator;
    var machine = Machine.init(input, allocator);

    const ast = try machine.parser.parse();
    defer ast.deinit(&allocator);

    const result = machine.eval(ast) catch @panic("Eval failed");
    defer result.deinit(&allocator);

    try testing.expect(result == .Number);
    try testing.expect(result.Number == 3);
}

test "evaluate simple multiplication" {
    const input = "(* 2 3)";
    var allocator = std.testing.allocator;
    var machine = Machine.init(input, allocator);

    const ast = try machine.parser.parse();
    defer ast.deinit(&allocator);

    const result = machine.eval(ast) catch @panic("Eval failed");
    defer result.deinit(&allocator);

    try testing.expect(result == .Number);
    try testing.expect(result.Number == 6);
}

test "evaluate simple division" {
    const input = "(/ 6 2)";
    var allocator = std.testing.allocator;
    var machine = Machine.init(input, allocator);

    const ast = try machine.parser.parse();
    defer ast.deinit(&allocator);

    const result = machine.eval(ast) catch @panic("Eval failed");
    defer result.deinit(&allocator);

    try testing.expect(result == .Number);
    try testing.expect(result.Number == 3);
}

test "evaluate nested expression" {
    const input = "(+ 1 (* 2 3))";
    var allocator = std.testing.allocator;
    var machine = Machine.init(input, allocator);

    const ast = try machine.parser.parse();
    defer ast.deinit(&allocator);

    const result = machine.eval(ast) catch @panic("Eval failed");
    defer result.deinit(&allocator);

    try testing.expect(result == .Number);
    try testing.expect(result.Number == 7);
}

test "evaluate recursive expression" {
    const input = "(- 10 (+ 2 3))";
    var allocator = std.testing.allocator;
    var machine = Machine.init(input, allocator);

    const ast = try machine.parser.parse();
    defer ast.deinit(&allocator);

    const result = machine.eval(ast) catch @panic("Eval failed");
    defer result.deinit(&allocator);

    try testing.expect(result == .Number);
    try testing.expect(result.Number == 5);
}

test "can evaluate complex expression" {
    const input = "(+ (- 5 1) (* 2 3))";
    var allocator = std.testing.allocator;
    var machine = Machine.init(input, allocator);

    const ast = try machine.parser.parse();
    defer ast.deinit(&allocator);

    const result = machine.eval(ast) catch @panic("Eval failed");
    defer result.deinit(&allocator);

    try testing.expect(result == .Number);
    std.debug.print("Result: {}\n", .{result.Number});
    try testing.expect(result.Number == 10);
}

// test "evaluate quoted expression" {
//     const input = "(+ (+ 1 2) 2)";
//     var allocator = std.testing.allocator;
//     var machine = Machine.init(input, allocator);
//     const ast = machine.parser.parse_expression();
//     defer ast.deinit(&allocator);

//     const result = machine.eval(ast) catch @panic("Eval failed");
//     defer result.deinit(&allocator);
// }
