const parser = @import("parser.zig");
const std = @import("std");
const machine = @import("machine.zig");
const Machine = machine.Machine;
const Context = machine.Context;
const builtin = @import("builtin.zig");
const Builtin = builtin.Builtin;
const BuiltinError = builtin.BuiltinError;
const GetBuiltIn = builtin.get_built_in;
const BoolToAst = builtin.bool_to_ast;

pub const nil: void = {};
pub const t: void = {};
pub const f: void = {};

pub fn @"+"(self: *Machine, ctx: *Context, args: []const *parser.AstNode) BuiltinError!*parser.AstNode {
    if (args.len == 0) {
        return error.InvalidArgument;
    }
    var sum: f64 = 0;
    for (args) |arg| {
        const output = try self.eval(ctx, arg);
        switch (output.value) {
            .number => |num| {
                sum += num;
            },
            else => {
                std.debug.panic("Invalid argument type: {?}", .{output.*});
                return error.InvalidType;
            },
        }
    }
    return try self.make_node(.{ .number = sum });
}

pub fn @"-"(self: *Machine, ctx: *Context, args: []const *parser.AstNode) BuiltinError!*parser.AstNode {
    if (args.len == 0) {
        return error.InvalidArgument;
    }
    var result: f64 = 0;
    for (args, 0..) |arg, i| {
        const output = try self.eval(ctx, arg);
        switch (output.value) {
            .number => |num| {
                if (i == 0 and args.len > 1) {
                    result = num;
                    continue;
                }
                result -= num;
            },
            else => {
                return error.InvalidType;
            },
        }
    }
    return try self.make_node(.{ .number = result });
}

pub fn @"*"(self: *Machine, ctx: *Context, args: []const *parser.AstNode) BuiltinError!*parser.AstNode {
    if (args.len == 0) {
        return error.InvalidArgument;
    }
    var product: f64 = 1;
    for (args) |arg| {
        const output = try self.eval(ctx, arg);
        switch (output.value) {
            .number => |num| {
                product *= num;
            },
            else => {
                return error.InvalidType;
            },
        }
    }
    return try self.make_node(.{ .number = product });
}

pub fn @"/"(self: *Machine, ctx: *Context, args: []const *parser.AstNode) BuiltinError!*parser.AstNode {
    if (args.len == 0) {
        return error.InvalidArgument;
    }
    var result: f64 = 1;
    for (args, 0..) |arg, index| {
        const output = try self.eval(ctx, arg);
        switch (output.value) {
            .number => |num| {
                if (index == 0 and args.len > 1) {
                    result = num;
                    continue;
                }
                result /= num;
            },
            else => {
                return error.InvalidType;
            },
        }
    }
    return try self.make_node(.{ .number = result });
}
pub fn @">"(self: *Machine, ctx: *Context, args: []const *parser.AstNode) BuiltinError!*parser.AstNode {
    if (args.len == 0) {
        return error.InvalidArgument;
    }
    var result: bool = true;
    for (args) |arg| {
        const output = try self.eval(ctx, arg);
        switch (output.value) {
            .number => |num| {
                result = result and num > 0;
            },
            else => {
                return error.InvalidType;
            },
        }
    }
    return BoolToAst(result);
}

pub fn @">="(self: *Machine, ctx: *Context, args: []const *parser.AstNode) BuiltinError!*parser.AstNode {
    if (args.len == 0) {
        return error.InvalidArgument;
    }
    var result: bool = true;
    for (args) |arg| {
        const output = try self.eval(ctx, arg);
        switch (output.value) {
            .number => |num| {
                result = result and num >= 0;
            },
            else => {
                return error.InvalidType;
            },
        }
    }
    return BoolToAst(result);
}

pub fn @"<"(self: *Machine, ctx: *Context, args: []const *parser.AstNode) BuiltinError!*parser.AstNode {
    if (args.len == 0) {
        return error.InvalidArgument;
    }
    var result: bool = true;
    for (args) |arg| {
        const output = try self.eval(ctx, arg);
        switch (output.value) {
            .number => |num| {
                result = result and num < 0;
            },
            else => {
                return error.InvalidType;
            },
        }
    }
    return BoolToAst(result);
}

pub fn @"<="(self: *Machine, ctx: *Context, args: []const *parser.AstNode) BuiltinError!*parser.AstNode {
    if (args.len == 0) {
        return error.InvalidArgument;
    }
    var result: bool = true;
    for (args) |arg| {
        const output = try self.eval(ctx, arg);
        switch (output.value) {
            .number => |num| {
                result = result and num <= 0;
            },
            else => {
                return error.InvalidType;
            },
        }
    }
    return BoolToAst(result);
}

pub fn @"="(self: *Machine, ctx: *Context, args: []const *parser.AstNode) BuiltinError!*parser.AstNode {
    if (args.len == 0) {
        return error.InvalidArgument;
    }
    var result: bool = false;
    for (args) |arg| {
        const output = try self.eval(ctx, arg);
        switch (output.value) {
            .number => |num| {
                result = result and num == 0;
            },
            else => {
                return error.InvalidType;
            },
        }
    }
    return BoolToAst(result);
}

pub fn defvar(
    self: *Machine,
    ctx: *Context,
    args: []const *parser.AstNode,
) BuiltinError!*parser.AstNode {
    if (args.len != 2) {
        return error.InvalidArgument;
    }
    const name = args[0].value.symbol;
    if (ctx.get(name) != null) {
        return error.SymbolAlreadyDefined;
    }
    const value = try self.eval(ctx, args[1]);
    try ctx.push(name, value);

    return value;
}

pub fn let(self: *Machine, ctx: *Context, args: []const *parser.AstNode) BuiltinError!*parser.AstNode {
    if (args.len < 2) {
        return error.InvalidParameterCount;
    }

    const new_ctx = try ctx.clone();
    defer new_ctx.deinit();
    for (args[0].value.list.items) |arg| {
        if (arg.value.list.items.len != 2) {
            return error.InvalidParameterCount;
        }
        const items = arg.value.list.items;
        const name = items[0].value.symbol;
        if (new_ctx.get(name) != null) {
            return error.SymbolAlreadyDefined;
        }
        const value = try self.eval(new_ctx, items[1]);
        try new_ctx.push(name, value);
    }

    var last_result = GetBuiltIn(.nil);
    for (args[1..]) |arg| {
        last_result = try self.eval(new_ctx, arg);
    }
    return last_result;
}

pub fn quote(
    self: *Machine,
    _: *Context,
    args: []const *parser.AstNode,
) BuiltinError!*parser.AstNode {
    if (args.len != 1) {
        return error.InvalidParameterCount;
    }
    if (args[0].value == .list) {
        const new_list = try self.make_node(.{ .list = std.ArrayList(*parser.AstNode).init(self.allocator) });
        for (args[0].value.list.items) |item| {
            try new_list.value.list.append(item);
        }
        args[0].value.list.clearRetainingCapacity();

        return new_list;
    }
    return args[0];
}

pub fn print(self: *Machine, ctx: *Context, args: []const *parser.AstNode) BuiltinError!*parser.AstNode {
    if (args.len == 0) {
        return error.InvalidArgument;
    }

    var output: *parser.AstNode = undefined;
    for (args) |arg| {
        output = try self.eval(ctx, arg);
        try print_internal(self, ctx, output);
    }
    std.debug.print("\n", .{});
    return output;
}

fn print_internal(
    self: *Machine,
    ctx: *Context,
    arg: *parser.AstNode,
) BuiltinError!void {
    if (arg == GetBuiltIn(.nil)) {
        std.debug.print("nil", .{});
        return;
    }
    switch (arg.value) {
        .number => |num| {
            std.debug.print("{d}", .{num});
        },
        .string => |str| {
            std.debug.print("{s}", .{str});
        },
        .symbol => |symbol| {
            std.debug.print("{s}", .{symbol});
        },
        .list => |list| {
            std.debug.print("(", .{});
            for (list.items, 0..) |item, i| {
                try print_internal(self, ctx, item);
                if (i != list.items.len - 1) {
                    std.debug.print(" ", .{});
                }
            }
            std.debug.print(")", .{});
        },
        else => {
            std.debug.print("{?}", .{arg.value});
        },
    }
}
