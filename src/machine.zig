const parser = @import("parser.zig");
const std = @import("std");
const testing = std.testing;

const builtins = @import("builtins.zig");
const builtin = @import("builtin.zig");

pub const Machine = struct {
    allocator: std.mem.Allocator,
    parser: parser.Parser,
    allocations: std.ArrayList(*parser.AstNode),
    // todo: add scoped variables, function labels, etc

    pub fn init(input: []const u8, allocator: std.mem.Allocator) Machine {
        return Machine{
            .allocator = allocator,
            .parser = parser.Parser.init(input, allocator),
            .allocations = std.ArrayList(*parser.AstNode).init(allocator),
        };
    }

    pub fn deinit(self: *Machine) void {
        self.parser.deinit();
        // any allocations need to be freed here.
        for (self.allocations.items) |item| {
            item.deinit(&self.allocator);
        }
        self.allocations.deinit();
    }

    pub fn eval(self: *Machine, ast: *parser.AstNode) !*parser.AstNode {
        switch (ast.*) {
            .List => |list| {
                if (list.items.len == 0) {
                    return ast;
                }
                const first = list.items[0];
                switch (first.*) {
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
                    else => {
                        std.debug.panic("Unknown expression type:", .{});
                    },
                }
            },
            .Number => |_| {
                return ast;
            },
            else => {},
        }
        return ast;
    }

    pub fn run(self: *Machine) !*parser.AstNode {
        const ast = self.parser.parse();
        for (ast.List.items) |item| {
            try self.eval(item);
        }
    }

    fn run_internal(self: *Machine) !*parser.AstNode {
        const ast = try self.parser.parse();
        for (ast.*.List.items) |item| {
            return try self.eval(item);
        }
        return error.InvalidArgument;
    }

    pub fn make_node(self: *Machine, node: parser.AstNode) !*parser.AstNode {
        const new_node = try self.allocator.create(parser.AstNode);
        new_node.* = node;
        try self.allocations.append(new_node);
        return new_node;
    }
};

fn deref_list(node: *parser.AstNode) parser.AstNode {
    return node.*.List.items[0].*;
}

fn deref_node(node: *parser.AstNode) parser.AstNode {
    return node.*;
}

fn run_and_get_output(
    input: []const u8,
    allocator: *std.mem.Allocator,
) !*parser.AstNode {
    var machine = Machine.init(input, allocator);
    defer machine.deinit();

    const output = try machine.run_internal();

    return output;
}

test "evaluate simple addition" {
    const input = "(+ 2 5)";
    const allocator = std.testing.allocator;
    var machine = Machine.init(input, allocator);
    defer machine.deinit();

    const output = try machine.run_internal();
    const result = deref_node(output);

    try testing.expect(result == .Number);
    try testing.expect(result.Number == 7);
}

test "evaluate simple subtraction" {
    const input = "(- 5 2)";
    const allocator = std.testing.allocator;
    var machine = Machine.init(input, allocator);
    defer machine.deinit();

    const output = try machine.run_internal();
    const result = deref_node(output);

    try testing.expect(result == .Number);
    try testing.expect(result.Number == 3);
}

test "evaluate simple multiplication" {
    const input = "(* 2 3)";
    const allocator = std.testing.allocator;
    var machine = Machine.init(input, allocator);
    defer machine.deinit();

    const output = try machine.run_internal();
    const result = deref_node(output);

    try testing.expect(result == .Number);
    try testing.expect(result.Number == 6);
}

test "evaluate simple division" {
    const input = "(/ 6 2)";
    const allocator = std.testing.allocator;
    var machine = Machine.init(input, allocator);
    defer machine.deinit();

    const output = try machine.run_internal();
    const result = deref_node(output);

    try testing.expect(result == .Number);
    try testing.expect(result.Number == 3);
}

test "evaluate nested expression" {
    const input = "(+ 1 (* 2 3))";
    const allocator = std.testing.allocator;
    var machine = Machine.init(input, allocator);
    defer machine.deinit();

    const output = try machine.run_internal();
    const result = deref_node(output);

    try testing.expect(result == .Number);
    try testing.expect(result.Number == 7);
}

test "evaluate recursive expression" {
    const input = "(- 10 (+ 2 3))";
    const allocator = std.testing.allocator;
    var machine = Machine.init(input, allocator);
    defer machine.deinit();

    const output = try machine.run_internal();
    const result = deref_node(output);

    try testing.expect(result == .Number);
    try testing.expect(result.Number == 5);
}

test "can evaluate complex expression" {
    const input = "(+ (+ (- 5 1) (* 2 3)) 2)";
    const allocator = std.testing.allocator;
    var machine = Machine.init(input, allocator);
    defer machine.deinit();

    const output = try machine.run_internal();
    const result = deref_node(output);

    try testing.expect(result == .Number);
    try testing.expect(result.Number == 12);
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
