const parser = @import("parser.zig");
const std = @import("std");
const testing = std.testing;

const builtins = @import("builtins.zig");
const builtin = @import("builtin.zig");

pub const Machine = struct {
    allocator: std.mem.Allocator,
    parser: parser.Parser,
    allocations: std.ArrayList(*parser.AstNode),
    global_vars: std.StringHashMap(*parser.AstNode),
    local_vars: std.StringHashMap(*parser.AstNode),

    pub fn init(input: []const u8, allocator: std.mem.Allocator) Machine {
        return Machine{
            .allocator = allocator,
            .parser = parser.Parser.init(input, allocator),
            .allocations = std.ArrayList(*parser.AstNode).init(allocator),
            .global_vars = std.StringHashMap(*parser.AstNode).init(allocator),
            .local_vars = std.StringHashMap(*parser.AstNode).init(allocator),
        };
    }

    pub fn deinit(self: *Machine) void {
        self.parser.deinit();
        // any allocations need to be freed here.
        for (self.allocations.items) |item| {
            item.deinit(&self.allocator);
        }
        self.allocations.deinit();
        self.global_vars.deinit();
        self.local_vars.deinit();
    }

    pub fn eval(self: *Machine, ast: *parser.AstNode) !*parser.AstNode {
        switch (ast.value) {
            .list => |list| {
                if (list.items.len == 0) {
                    return builtin.getBuiltin(.nil);
                }
                const first = list.items[0];
                switch (first.value) {
                    .symbol => |symbol| {
                        // try to evaluate the symbol
                        const output = try self.eval(first);
                        if (!output.isNil()) {
                            return output;
                        }

                        const e = std.meta.stringToEnum(builtin.Builtin, symbol);
                        if (e != null) {
                            const builtin_fn = builtin.getBuiltin(e.?).value.function;
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
            .number => |_| {
                return ast;
            },
            .symbol => {
                // Check if the symbol is a local variable
                const local_var = self.local_vars.get(ast.value.symbol);
                if (local_var) |local| {
                    return local;
                }
                // Check if the symbol is a global variable
                const global_var = self.global_vars.get(ast.value.symbol);
                if (global_var) |global| {
                    return global;
                }

                return builtin.getBuiltin(.nil);
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
        for (ast.value.list.items) |item| {
            node = try self.eval(item);
        }
        return node;
    }
};

fn deref_list(node: *parser.AstNode) parser.AstNode {
    return node.value.list.items[0].*;
}

fn deref_node(node: *parser.AstNode) parser.AstNode {
    return node.*;
}

fn run_and_get_output(
    input: []const u8,
    allocator: std.mem.Allocator,
) !parser.AstNode {
    var machine = Machine.init(input, allocator);
    defer machine.deinit();

    const output = try machine.run_internal();
    const result = deref_node(output);

    return result;
}

test "evaluate simple addition" {
    const result = try run_and_get_output("(+ 2 5)", std.testing.allocator);

    try testing.expect(result.value == .number);
    try testing.expect(result.value.number == 7);
}

test "evaluate simple subtraction" {
    const result = try run_and_get_output("(- 5 2)", std.testing.allocator);

    try testing.expect(result.value == .number);
    try testing.expect(result.value.number == 3);
}

test "evaluate simple multiplication" {
    const result = try run_and_get_output("(* 2 3)", std.testing.allocator);

    try testing.expect(result.value == .number);
    try testing.expect(result.value.number == 6);
}

test "evaluate simple division" {
    const result = try run_and_get_output("(/ 6 2)", std.testing.allocator);

    try testing.expect(result.value == .number);
    try testing.expect(result.value.number == 3);
}

test "evaluate nested expression" {
    const result = try run_and_get_output("(+ 1 (* 2 3))", std.testing.allocator);
    try testing.expect(result.value == .number);
    try testing.expect(result.value.number == 7);
}

test "evaluate recursive expression" {
    const result = try run_and_get_output("(defvar x 5) (+ x 10)", std.testing.allocator);
    try testing.expect(result.value == .number);
    try testing.expect(result.value.number == 15);
}

test "can evaluate complex expression" {
    const input = "(+ (+ (- 5 1) (* 2 3)) 2)";
    const result = try run_and_get_output(input, std.testing.allocator);

    try testing.expect(result.value == .number);
    try testing.expect(result.value.number == 12);
}

test "can evaluate complex expression with nested variables" {
    const input = "(defvar x 5) (defvar y (+ x 10)) (+ y 5)";
    const result = try run_and_get_output(input, std.testing.allocator);

    try testing.expect(result.value == .number);
    try testing.expect(result.value.number == 20);
}

test "can evaluate let statement" {
    const result = try run_and_get_output("(let ((x 5))(+ x 10))", std.testing.allocator);
    try testing.expect(result.value == .number);
    try testing.expect(result.value.number == 15);
}
