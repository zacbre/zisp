const parser = @import("parser.zig");
const std = @import("std");
const machine = @import("machine.zig");
const Machine = machine.Machine;
const Context = machine.Context;
const BuiltinError = @import("builtin.zig").BuiltinError;
const GetBuiltIn = @import("builtin.zig").getBuiltin;

pub const nil: void = {};

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
    return try self.make_node(.{ .boolean = result });
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
    return try self.make_node(.{ .boolean = result });
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
    return try self.make_node(.{ .boolean = result });
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
    return try self.make_node(.{ .boolean = result });
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
    return try self.make_node(.{ .boolean = result });
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

pub fn print(self: *Machine, ctx: *Context, args: []const *parser.AstNode) BuiltinError!*parser.AstNode {
    return try print_internal(self, ctx, args, 0);
}

fn print_internal(
    self: *Machine,
    ctx: *Context,
    args: []const *parser.AstNode,
    level: usize,
) BuiltinError!*parser.AstNode {
    if (args.len == 0) {
        return error.InvalidArgument;
    }
    if (level > 0) {
        for (0..level) |_| {
            std.debug.print("\t", .{});
        }
    }
    for (args) |arg| {
        const output = try self.eval(ctx, arg);
        switch (output.value) {
            .boolean => |b| {
                std.debug.print("{any}", .{b});
            },
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
                std.debug.print("[", .{});
                _ = try print_internal(self, ctx, list.items, level + 1);
                std.debug.print("]", .{});
            },
            else => {
                std.debug.print("{?}", .{output});
            },
        }
    }
    std.debug.print("\n", .{});
    return GetBuiltIn(.nil);
}
