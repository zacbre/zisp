const parser = @import("parser.zig");
const std = @import("std");
const machine = @import("machine.zig");
const Machine = machine.Machine;
const BuiltinError = @import("builtin.zig").BuiltinError;

pub const nil: void = {};

pub fn @"+"(self: *Machine, args: []const *parser.AstNode) BuiltinError!*parser.AstNode {
    if (args.len == 0) {
        return error.InvalidArgument;
    }
    var sum: f64 = 0;
    for (args) |arg| {
        std.debug.print("arg: {any}\n", .{arg.value});
        const output = try self.eval(arg);
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

pub fn @"-"(self: *Machine, args: []const *parser.AstNode) BuiltinError!*parser.AstNode {
    if (args.len == 0) {
        return error.InvalidArgument;
    }
    var result: f64 = 0;
    for (args, 0..) |arg, i| {
        const output = try self.eval(arg);
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

pub fn @"*"(self: *Machine, args: []const *parser.AstNode) BuiltinError!*parser.AstNode {
    if (args.len == 0) {
        return error.InvalidArgument;
    }
    var product: f64 = 1;
    for (args) |arg| {
        const output = try self.eval(arg);
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

pub fn @"/"(self: *Machine, args: []const *parser.AstNode) BuiltinError!*parser.AstNode {
    if (args.len == 0) {
        return error.InvalidArgument;
    }
    var result: f64 = 1;
    for (args, 0..) |arg, index| {
        const output = try self.eval(arg);
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
pub fn @">"(self: *Machine, args: []const *parser.AstNode) BuiltinError!*parser.AstNode {
    if (args.len == 0) {
        return error.InvalidArgument;
    }
    var result: bool = true;
    for (args) |arg| {
        const output = try self.eval(arg);
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

pub fn @">="(self: *Machine, args: []const *parser.AstNode) BuiltinError!*parser.AstNode {
    if (args.len == 0) {
        return error.InvalidArgument;
    }
    var result: bool = true;
    for (args) |arg| {
        const output = try self.eval(arg);
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

pub fn @"<"(self: *Machine, args: []const *parser.AstNode) BuiltinError!*parser.AstNode {
    if (args.len == 0) {
        return error.InvalidArgument;
    }
    var result: bool = true;
    for (args) |arg| {
        const output = try self.eval(arg);
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

pub fn @"<="(self: *Machine, args: []const *parser.AstNode) BuiltinError!*parser.AstNode {
    if (args.len == 0) {
        return error.InvalidArgument;
    }
    var result: bool = true;
    for (args) |arg| {
        const output = try self.eval(arg);
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

pub fn @"="(self: *Machine, args: []const *parser.AstNode) BuiltinError!*parser.AstNode {
    if (args.len == 0) {
        return error.InvalidArgument;
    }
    var result: bool = false;
    for (args) |arg| {
        const output = try self.eval(arg);
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
    args: []const *parser.AstNode,
) BuiltinError!*parser.AstNode {
    if (args.len != 2) {
        return error.InvalidArgument;
    }
    const name = args[0].value.symbol;
    const value = try self.eval(args[1]);
    const node = try self.make_node(.{ .symbol = name });
    node.* = value.*;
    try self.global_vars.put(name, node);

    return node;
}

pub fn let(self: *Machine, args: []const *parser.AstNode) BuiltinError!*parser.AstNode {
    if (args.len != 2) {
        return error.InvalidArgument;
    }

    args[1].context = try parser.Context.init(self.allocator);

    for (args[0].value.list.items) |arg| {
        // arg will be lists in the format of: (a 10) or (a '10) or (a 10) or (a b)
        if (arg.value.list.items.len != 2) {
            return error.InvalidArgument;
        }
        const items = arg.value.list.items;
        const name = items[0].value.symbol;
        if (self.global_vars.get(name) != null or args[1].context.?.get(name) != null) {
            return error.VariableAlreadyDefined;
        }
        const value = try self.eval(items[1]);
        args[1].context.?.push(name, value);
    }

    const output = try self.eval(args[1]);
    args[1].context.?.deinit();
    return output;
}
