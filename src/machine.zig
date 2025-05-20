const parser = @import("parser.zig");
const std = @import("std");
const testing = std.testing;

const builtins = @import("builtins.zig");
const builtin = @import("builtin.zig");

pub const Machine = struct {
    allocator: std.mem.Allocator,
    parser: parser.Parser,
    allocations: std.ArrayList(*parser.AstNode),
    variable_map: std.StringHashMap(*parser.AstNode),

    pub fn init(input: []const u8, allocator: std.mem.Allocator) Machine {
        return Machine{
            .allocator = allocator,
            .parser = parser.Parser.init(input, allocator),
            .allocations = std.ArrayList(*parser.AstNode).init(allocator),
            .variable_map = std.StringHashMap(*parser.AstNode).init(allocator),
        };
    }

    pub fn deinit(self: *Machine) void {
        self.parser.deinit();
        // any allocations need to be freed here.
        for (self.allocations.items) |item| {
            item.deinit(&self.allocator);
        }
        self.allocations.deinit();
        self.variable_map.deinit();
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
                        // Check if the symbol is a variable
                        const variable = self.variable_map.get(symbol);
                        if (variable) |vari| {
                            return vari;
                        }

                        const e = std.meta.stringToEnum(builtin.Builtin, symbol);
                        if (e != null) {
                            const builtin_fn = builtin.getBuiltin(e.?).*.Function;
                            const result = builtin_fn(self, list.items[1..]) catch |err| {
                                std.debug.panic("Builtin error: {}", .{err});
                            };
                            return result;
                        } else {
                            // Handle the case where the symbol is not a builtin
                            std.debug.panic("Unknown symbol: {s}\n", .{symbol});
                        }
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
            .Symbol => {
                const variable = self.variable_map.get(ast.*.Symbol);
                if (variable) |vari| {
                    return vari;
                }
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

    pub fn make_node(self: *Machine, node: parser.AstNode) !*parser.AstNode {
        const new_node = try self.allocator.create(parser.AstNode);
        new_node.* = node;
        try self.allocations.append(new_node);
        return new_node;
    }

    fn run_internal(self: *Machine) !*parser.AstNode {
        const ast = try self.parser.parse();
        var node = ast;
        for (ast.*.List.items) |item| {
            node = try self.eval(item);
        }
        return node;
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

test "can evaluate complex expression with nested variables" {
    const input = "(defvar x 5) (defvar y (+ x 10)) (+ y 5)";
    const allocator = std.testing.allocator;
    var machine = Machine.init(input, allocator);
    defer machine.deinit();

    const output = try machine.run_internal();
    const result = deref_node(output);

    try testing.expect(result == .Number);
    try testing.expect(result.Number == 20);
}
