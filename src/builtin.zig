const std = @import("std");
const builtins = @import("builtins.zig");
const AstNode = @import("parser.zig").AstNode;
const machine = @import("machine.zig");
const Machine = machine.Machine;
const Context = machine.Context;

const EnumField = std.builtin.Type.EnumField;

pub const BuiltinError = error{
    InvalidParameterCount,
    InvalidArgument,
    InvalidType,
    OutOfMemory,
    SymbolAlreadyDefined,
    SymbolUndefined,
};

pub const BuiltinFn = *const fn (machine: *Machine, ctx: *Context, []const *AstNode) BuiltinError!*AstNode;

pub const Builtin = v: {
    const decls = std.meta.declarations(builtins);

    var generated_fields_array: [decls.len]EnumField = undefined;
    for (decls, 0..) |decl, i| {
        generated_fields_array[i] = .{
            .name = decl.name,
            .value = i,
        };
    }
    const fields_slice: []const EnumField = if (decls.len == 0) &[_]EnumField{} else &generated_fields_array;
    const enum_tag_type = if (decls.len == 0) void else std.math.IntFittingRange(0, decls.len - 1);

    break :v @Type(.{
        .@"enum" = .{
            .fields = fields_slice,
            .tag_type = enum_tag_type,
            .decls = &[_]std.builtin.Type.Declaration{},
            .is_exhaustive = true,
        },
    });
};

pub const builtin_map = v: {
    const builtin_fields = std.meta.fields(Builtin);
    var arr: [builtin_fields.len]*const AstNode = undefined;

    for (builtin_fields) |f| {
        const tag = @field(Builtin, f.name);
        if (@hasDecl(builtins, @tagName(tag))) {
            const field = @field(builtins, f.name);
            arr[@intFromEnum(tag)] = switch (@typeInfo(@TypeOf(field))) {
                .@"fn" => &AstNode{ .value = .{ .function = @field(builtins, f.name) } },
                .void => &AstNode{ .value = .{ .symbol = f.name } },
                else => @compileError("Unsupported type for intrinsic named " ++ f.name),
            };
        } else @compileError("All public decls should have a generated Intrinsic entry");
    }

    break :v arr;
};

//.print

pub fn get_built_in(tag: Builtin) *AstNode {
    return @constCast(builtin_map[@intFromEnum(tag)]);
}

pub fn bool_to_ast(value: bool) *AstNode {
    return if (value)
        get_built_in(.t)
    else
        get_built_in(.nil);
}

pub fn ast_to_bool(node: *AstNode) bool {
    return std.meta.eql(node.value, get_built_in(.t).value);
}

test "can convert bool to ast and back" {
    const true_ast = bool_to_ast(true);
    const false_ast = bool_to_ast(false);
    const true_bool = ast_to_bool(get_built_in(.t));
    const false_bool = ast_to_bool(get_built_in(.nil));

    try std.testing.expect(true_ast == get_built_in(.t));
    try std.testing.expect(false_ast == get_built_in(.nil));
    try std.testing.expect(true_bool == true);
    try std.testing.expect(false_bool == false);
}
