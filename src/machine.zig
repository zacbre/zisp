const parser = @import("parser.zig");
const std = @import("std");
const testing = std.testing;

const builtins = @import("builtins.zig");
const builtin = @import("builtin.zig");

pub const Context = struct {
    vars: std.StringHashMap(*parser.AstNode),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !*Context {
        const context = try allocator.create(Context);
        context.vars = std.StringHashMap(*parser.AstNode).init(allocator);
        context.allocator = allocator;
        return context;
    }

    pub fn deinit(self: *Context) void {
        self.vars.deinit();
        self.allocator.destroy(self);
    }

    pub fn clone(self: *Context) !*Context {
        const new_context = try self.allocator.create(Context);
        new_context.vars = try self.vars.clone();
        new_context.allocator = self.allocator;
        return new_context;
    }

    pub fn push(self: *Context, key: []const u8, value: *parser.AstNode) !void {
        try self.vars.put(key, value);
    }

    pub fn get(self: *Context, key: []const u8) ?*parser.AstNode {
        return self.vars.get(key);
    }
};

pub const Machine = struct {
    allocator: std.mem.Allocator,
    parser: parser.Parser,
    allocations: std.ArrayList(*parser.AstNode),
    context: *Context,

    pub fn init(input: []const u8, allocator: std.mem.Allocator) Machine {
        return Machine{
            .allocator = allocator,
            .parser = parser.Parser.init(input, allocator),
            .allocations = std.ArrayList(*parser.AstNode).init(allocator),
            .context = Context.init(allocator) catch |err| {
                std.debug.panic("Failed to initialize context: {}", .{err});
            },
        };
    }

    pub fn deinit(self: *Machine) void {
        self.parser.deinit();
        // any allocations need to be freed here.
        for (self.allocations.items) |item| {
            item.deinit(&self.allocator);
        }
        self.allocations.deinit();
        self.context.deinit();
    }

    pub fn eval(self: *Machine, ctx: *Context, ast: *parser.AstNode) !*parser.AstNode {
        return switch (ast.value) {
            .list => |list| {
                if (list.items.len == 0) {
                    return builtin.getBuiltin(.nil);
                }
                const first = list.items[0];
                switch (first.value) {
                    .symbol => |symbol| {
                        const output = self.eval(ctx, first) catch {
                            const e = std.meta.stringToEnum(builtin.Builtin, symbol);
                            if (e != null) {
                                const builtin_fn = builtin.getBuiltin(e.?).value.function;
                                const result = try builtin_fn(self, ctx, list.items[1..]);
                                return result;
                            } else {
                                // Handle the case where the symbol is not a builtin
                                std.debug.panic("Unknown symbol: {s}\n", .{symbol});
                            }
                        };

                        return output;
                    },
                    else => {
                        return try self.eval(ctx, first);
                    },
                }
            },
            .symbol => {
                if (ctx.get(ast.value.symbol)) |local| {
                    return local;
                }

                return error.SymbolUndefined;
            },
            .quoted => |quoted| {
                return quoted;
            },
            else => {
                return ast;
            },
        };
    }

    pub fn run(self: *Machine) !*parser.AstNode {
        const ast = self.parser.parse();
        for (ast.List.items) |item| {
            try self.eval(item);
        }
    }

    pub fn make_node(self: *Machine, node: parser.AstNodeValue) !*parser.AstNode {
        const new_node = try parser.AstNode.new(node, self.allocator);
        try self.allocations.append(new_node);
        return new_node;
    }

    fn run_internal(self: *Machine) !*parser.AstNode {
        const ast = try self.parser.parse();
        var node = ast;
        for (ast.value.list.items) |item| {
            node = try self.eval(self.context, item);
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

test "post let statement does not contain scoped variables" {
    const result = run_and_get_output("(let ((x 5))(+ x 10)) (+ x 10)", std.testing.allocator);
    try std.testing.expectError(builtin.BuiltinError.SymbolUndefined, result);
}

test "redefining variables returns an error" {
    const result = run_and_get_output("(defvar x 5) (defvar x 10)", std.testing.allocator);
    try std.testing.expectError(builtin.BuiltinError.SymbolAlreadyDefined, result);
}

test "redefining variables in let returns an error" {
    const result = run_and_get_output("(let ((x 5) (x 10)) (+ x 10))", std.testing.allocator);
    try std.testing.expectError(builtin.BuiltinError.SymbolAlreadyDefined, result);
}

test "redefining global variables with let returns an error" {
    const result = run_and_get_output("(defvar x 5) (let ((x 10)) (+ x 10))", std.testing.allocator);
    try std.testing.expectError(builtin.BuiltinError.SymbolAlreadyDefined, result);
}

test "can evaluate statement with global and local variables" {
    const result = try run_and_get_output("(defvar x 5) (let ((y 10)) (+ x y))", std.testing.allocator);
    try testing.expect(result.value == .number);
    try testing.expect(result.value.number == 15);
}

test "don't evaluate quoted statement" {
    var machine = Machine.init("('(+ 1 2))", std.testing.allocator);
    defer machine.deinit();

    const output = try machine.run_internal();
    const result = deref_list(output);

    try testing.expect(result.value == .list);
    try testing.expect(result.value.list.items.len == 3);
    try testing.expect(result.value.list.items[0].value == .symbol);
    try testing.expect(std.mem.eql(u8, result.value.list.items[0].value.symbol, "+"));
    try testing.expect(result.value.list.items[1].value == .number);
    try testing.expect(result.value.list.items[1].value.number == 1);
    try testing.expect(result.value.list.items[2].value == .number);
    try testing.expect(result.value.list.items[2].value.number == 2);
}
