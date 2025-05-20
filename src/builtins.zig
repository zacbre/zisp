const parser = @import("parser.zig");
const std = @import("std");
const machine = @import("machine.zig");
const Machine = machine.Machine;
const BuiltinError = @import("builtin.zig").BuiltinError;

pub fn @"+"(self: *Machine, args: []const *parser.AstNode) BuiltinError!*parser.AstNode {
    if (args.len == 0) {
        return error.InvalidArgument;
    }
    var sum: f64 = 0;
    for (args) |arg| {
        const output = try self.eval(arg);
        switch (output.*) {
            .Number => |num| {
                sum += num;
            },
            else => {
                return error.InvalidType;
            },
        }
    }
    return try self.make_node(parser.AstNode{ .Number = sum });
}

pub fn @"-"(self: *Machine, args: []const *parser.AstNode) BuiltinError!*parser.AstNode {
    if (args.len == 0) {
        return error.InvalidArgument;
    }
    var result: f64 = 0;
    for (args, 0..) |arg, i| {
        const output = try self.eval(arg);
        switch (output.*) {
            .Number => |num| {
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
    return try self.make_node(parser.AstNode{ .Number = result });
}

pub fn @"*"(self: *Machine, args: []const *parser.AstNode) BuiltinError!*parser.AstNode {
    if (args.len == 0) {
        return error.InvalidArgument;
    }
    var product: f64 = 1;
    for (args) |arg| {
        const output = try self.eval(arg);
        switch (output.*) {
            .Number => |num| {
                product *= num;
            },
            else => {
                return error.InvalidType;
            },
        }
    }
    return try self.make_node(parser.AstNode{ .Number = product });
}

pub fn @"/"(self: *Machine, args: []const *parser.AstNode) BuiltinError!*parser.AstNode {
    if (args.len == 0) {
        return error.InvalidArgument;
    }
    var result: f64 = 1;
    for (args, 0..) |arg, index| {
        const output = try self.eval(arg);
        switch (output.*) {
            .Number => |num| {
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
    return try self.make_node(parser.AstNode{ .Number = result });
}
pub fn @">"(self: *Machine, args: []const *parser.AstNode) BuiltinError!*parser.AstNode {
    if (args.len == 0) {
        return error.InvalidArgument;
    }
    var result: bool = true;
    for (args) |arg| {
        const output = try self.eval(arg);
        switch (output.*) {
            .Number => |num| {
                result = result and num > 0;
            },
            else => {
                return error.InvalidType;
            },
        }
    }
    return try self.make_node(parser.AstNode{ .Boolean = result });
}

pub fn @">="(self: *Machine, args: []const *parser.AstNode) BuiltinError!*parser.AstNode {
    if (args.len == 0) {
        return error.InvalidArgument;
    }
    var result: bool = true;
    for (args) |arg| {
        const output = try self.eval(arg);
        switch (output.*) {
            .Number => |num| {
                result = result and num >= 0;
            },
            else => {
                return error.InvalidType;
            },
        }
    }
    return try self.make_node(parser.AstNode{ .Boolean = result });
}

pub fn @"<"(self: *Machine, args: []const *parser.AstNode) BuiltinError!*parser.AstNode {
    if (args.len == 0) {
        return error.InvalidArgument;
    }
    var result: bool = true;
    for (args) |arg| {
        const output = try self.eval(arg);
        switch (output.*) {
            .Number => |num| {
                result = result and num < 0;
            },
            else => {
                return error.InvalidType;
            },
        }
    }
    return try self.make_node(parser.AstNode{ .Boolean = result });
}

pub fn @"<="(self: *Machine, args: []const *parser.AstNode) BuiltinError!*parser.AstNode {
    if (args.len == 0) {
        return error.InvalidArgument;
    }
    var result: bool = true;
    for (args) |arg| {
        const output = try self.eval(arg);
        switch (output.*) {
            .Number => |num| {
                result = result and num <= 0;
            },
            else => {
                return error.InvalidType;
            },
        }
    }
    return try self.make_node(parser.AstNode{ .Boolean = result });
}

pub fn @"="(self: *Machine, args: []const *parser.AstNode) BuiltinError!*parser.AstNode {
    if (args.len == 0) {
        return error.InvalidArgument;
    }
    var result: bool = true;
    for (args) |arg| {
        const output = try self.eval(arg);
        switch (output.*) {
            .Number => |num| {
                result = result and num == 0;
            },
            else => {
                return error.InvalidType;
            },
        }
    }
    return try self.make_node(parser.AstNode{ .Boolean = result });
}

pub fn defvar(
    self: *Machine,
    args: []const *parser.AstNode,
) BuiltinError!*parser.AstNode {
    if (args.len != 2) {
        return error.InvalidArgument;
    }
    const name = args[0].*.Symbol;
    const value = try self.eval(args[1]);
    const node = try self.make_node(parser.AstNode{ .Symbol = name });
    node.* = value.*;
    try self.variable_map.put(name, node);

    return node;
}
