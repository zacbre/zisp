const lexer = @import("lexer.zig");
const std = @import("std");
const testing = std.testing;

const TokenKind = lexer.TokenKind;
const Token = lexer.Token;
const Lexer = lexer.Lexer;

const BuiltinFn = @import("builtin.zig").BuiltinFn;
const builtin = @import("builtin.zig");

pub const AstNodeKind = enum(u8) {
    symbol,
    number,
    list,
    string,
    boolean,
    function,
};

pub const AstNodeValue = union(AstNodeKind) {
    symbol: []const u8,
    number: f64,
    list: std.ArrayList(*AstNode),
    string: []const u8,
    boolean: bool,
    function: BuiltinFn,
};

pub const AstNode = struct {
    value: AstNodeValue,

    pub fn new(value: AstNodeValue, allocator: std.mem.Allocator) !*AstNode {
        const node = try allocator.create(AstNode);
        node.value = value;
        return node;
    }

    pub fn deinit(self: *AstNode, allocator: *std.mem.Allocator) void {
        switch (self.value) {
            .list => |list| {
                for (list.items) |node| {
                    node.deinit(allocator);
                }
                list.deinit();
            },
            else => {},
        }
        allocator.destroy(self);
    }

    pub fn isBuiltin(self: *@This(), tag: builtin.Builtin) bool {
        const bin = builtin.getBuiltin(tag);
        if (self == bin) {
            return true;
        }

        return switch (self.value) {
            .function => |f| bin.value == .function and bin.value.function == f,
            .symbol => |s| bin.value == .symbol and bin.value.symbol.ptr == s.ptr,
            .number => |n| bin.value == .number and bin.value.number == n,
            else => false,
        };
    }

    pub fn isNil(self: *@This()) bool {
        return self.isBuiltin(.nil);
    }
};

pub const Parser = struct {
    allocator: std.mem.Allocator,
    lexer: Lexer,
    current_token: Token,
    current_node: *AstNode,
    node_stack: std.ArrayList(*AstNode),

    pub fn init(input: []const u8, allocator: std.mem.Allocator) Parser {
        var p = Parser{
            .lexer = Lexer.init(input),
            .allocator = allocator,
            .current_token = Token{ .kind = TokenKind.EOF, .value = "" },
            .current_node = builtin.getBuiltin(.nil),
            .node_stack = std.ArrayList(*AstNode).init(allocator),
        };

        p.next_token();
        return p;
    }

    pub fn deinit(self: *Parser) void {
        self.current_node.deinit(&self.allocator);
        self.node_stack.deinit();
    }

    pub fn parse(self: *Parser) !*AstNode {
        self.current_node = try self.make_node(.{ .list = std.ArrayList(*AstNode).init(self.allocator) });

        while (true) {
            switch (self.current_token.kind) {
                TokenKind.LPAREN => {
                    self.next_token();
                    try self.node_stack.append(self.current_node);
                    self.current_node = try self.make_node(.{ .list = std.ArrayList(*AstNode).init(self.allocator) });
                },
                TokenKind.RPAREN => {
                    self.next_token();
                    if (self.node_stack.items.len == 0) {
                        std.debug.panic("Unexpected closing parenthesis", .{});
                    }
                    const old_node = self.current_node;
                    const popped_node = self.node_stack.pop();
                    if (popped_node == null) {
                        std.debug.panic("Failed to pop node from stack", .{});
                    }
                    self.current_node = popped_node.?;
                    try self.current_node.value.list.append(old_node);
                },
                TokenKind.QUOTE => {
                    self.next_token();
                    const current_node_copy = self.current_node;
                    const quoted = try self.parse();
                    // we really should change this into a symbol called quote with args.
                    const inner = try self.make_node(.{ .list = std.ArrayList(*AstNode).init(self.allocator) });
                    try inner.value.list.append(try self.make_node(.{ .symbol = "quote" }));
                    try inner.value.list.append(quoted.value.list.items[0]);

                    quoted.value.list.deinit();
                    self.allocator.destroy(quoted);

                    self.current_node = current_node_copy;
                    try self.current_node.value.list.append(inner);
                },
                TokenKind.NUMBER => {
                    const value = std.fmt.parseFloat(f64, self.current_token.value) catch {
                        std.debug.panic("Failed to parse float: {d}", .{self.current_token.value});
                    };
                    self.next_token();
                    try self.current_node.value.list.append(try self.make_node(.{ .number = value }));
                },
                TokenKind.IDENTIFIER => {
                    const value = self.current_token.value;
                    self.next_token();
                    try self.current_node.value.list.append(try self.make_node(.{ .symbol = value }));
                },
                TokenKind.STRING => {
                    const value = self.current_token.value;
                    self.next_token();
                    try self.current_node.value.list.append(try self.make_node(.{ .string = value }));
                },
                TokenKind.BOOLEAN => {
                    const value = if (std.mem.eql(u8, self.current_token.value, "#t")) true else false;
                    self.next_token();
                    try self.current_node.value.list.append(try self.make_node(.{ .boolean = value }));
                },
                TokenKind.EOF => {
                    if (self.node_stack.items.len > 0) {
                        std.debug.panic("Unexpected end of input", .{});
                    }
                    return self.current_node;
                },
                else => {
                    std.debug.panic("Unexpected token: {s}", .{self.current_token.value});
                },
            }
        }
    }

    fn next_token(self: *Parser) void {
        self.current_token = self.lexer.next_token();
    }

    fn make_node(self: *Parser, node: AstNodeValue) !*AstNode {
        return try AstNode.new(node, self.allocator);
    }
};

fn deref_list(node: *AstNode) AstNode {
    return node.value.list.items[0].*;
}

test "can parse a simple expression" {
    const allocator = std.testing.allocator;
    var parser = Parser.init("(+ 1 2)", allocator);
    defer parser.deinit();

    const output = try parser.parse();
    const node = deref_list(output);

    try testing.expect(node.value.list.items.len == 3);
    try testing.expect(std.mem.eql(u8, node.value.list.items[0].value.symbol, "+"));
    try testing.expect(node.value.list.items[1].value.number == 1);
    try testing.expect(node.value.list.items[2].value.number == 2);
}

test "can parse a quoted expression" {
    const allocator = std.testing.allocator;
    var parser = Parser.init("'(1 2)", allocator);
    defer parser.deinit();
    const output = try parser.parse();

    const result = deref_list(output);

    try testing.expect(result.value.list.items.len == 2);
    try testing.expect(std.mem.eql(u8, result.value.list.items[0].value.symbol, "quote"));
    try testing.expect(result.value.list.items[1].value.list.items.len == 2);
}

test "can parse a string" {
    const allocator = std.testing.allocator;
    var parser = Parser.init("\"hello\"", allocator);
    defer parser.deinit();

    const output = try parser.parse();
    const node = deref_list(output);

    try testing.expect(std.mem.eql(u8, node.value.string, "hello"));
}

test "can parse a boolean" {
    const allocator = std.testing.allocator;
    var parser = Parser.init("#t", allocator);

    const output = try parser.parse();
    const node = deref_list(output);

    try testing.expect(node.value.boolean == true);
    parser.deinit();

    parser = Parser.init("#f", allocator);
    const output2 = try parser.parse();
    const node2 = deref_list(output2);

    try testing.expect(node2.value.boolean == false);
    parser.deinit();
}
test "can parse a number" {
    const allocator = std.testing.allocator;
    var parser = Parser.init("42", allocator);
    defer parser.deinit();
    const output = try parser.parse();
    const node = deref_list(output);
    try testing.expect(node.value.number == 42);
}

test "can parse an identifier" {
    const allocator = std.testing.allocator;
    var parser = Parser.init("foo", allocator);
    defer parser.deinit();
    const output = try parser.parse();
    const node = deref_list(output);
    try testing.expect(std.mem.eql(u8, node.value.symbol, "foo"));
}

test "can parse a list with mixed types" {
    const allocator = std.testing.allocator;
    var parser = Parser.init("(foo 42 123.456 \"bar\" #t)", allocator);
    defer parser.deinit();
    const output = try parser.parse();

    const node = deref_list(output);
    try testing.expect(node.value.list.items.len == 5);
    try testing.expect(std.mem.eql(u8, node.value.list.items[0].value.symbol, "foo"));
    try testing.expect(node.value.list.items[1].value.number == 42);
    try testing.expect(std.math.approxEqAbs(f64, node.value.list.items[2].value.number, 123.456, 0.0001));
    try testing.expect(std.mem.eql(u8, node.value.list.items[3].value.string, "bar"));
    try testing.expect(node.value.list.items[4].value.boolean == true);
}

test "can parse nested expression" {
    const allocator = std.testing.allocator;
    var parser = Parser.init("(foo (bar 42) (baz 123))", allocator);
    defer parser.deinit();

    const output = try parser.parse();
    const node = deref_list(output);
    try testing.expect(node.value.list.items.len == 3);
    try testing.expect(std.mem.eql(u8, node.value.list.items[0].value.symbol, "foo"));
    try testing.expect(node.value.list.items[1].value.list.items.len == 2);
    try testing.expect(std.mem.eql(u8, node.value.list.items[1].value.list.items[0].value.symbol, "bar"));
    try testing.expect(node.value.list.items[1].value.list.items[1].value.number == 42);
    try testing.expect(node.value.list.items[2].value.list.items.len == 2);
    try testing.expect(std.mem.eql(u8, node.value.list.items[2].value.list.items[0].value.symbol, "baz"));
    try testing.expect(node.value.list.items[2].value.list.items[1].value.number == 123);
}

test "can parse nested list" {
    const allocator = std.testing.allocator;
    var parser = Parser.init("(let ((x 10)(y 15)) (+ x y))", allocator);
    defer parser.deinit();

    const output = try parser.parse();
    const node = deref_list(output);
    try testing.expect(node.value.list.items.len == 3);
    try testing.expect(std.mem.eql(u8, node.value.list.items[0].value.symbol, "let"));
    const first_item = node.value.list.items[1].value;

    try testing.expect(first_item.list.items.len == 2);
    const item_sublist_1 = first_item.list.items[0];
    try testing.expect(item_sublist_1.value.list.items.len == 2);
    const item_sublist_1_items = item_sublist_1.value.list.items;
    try testing.expect(std.mem.eql(u8, item_sublist_1_items[0].value.symbol, "x"));
    try testing.expect(item_sublist_1_items[1].value.number == 10);
    const item_sublist_2 = first_item.list.items[1];
    try testing.expect(item_sublist_2.value.list.items.len == 2);
    const item_sublist_2_items = item_sublist_2.value.list.items;
    try testing.expect(std.mem.eql(u8, item_sublist_2_items[0].value.symbol, "y"));
    try testing.expect(item_sublist_2_items[1].value.number == 15);
    const last_item = node.value.list.items[2];
    try testing.expect(last_item.value.list.items.len == 3);
    try testing.expect(std.mem.eql(u8, last_item.value.list.items[0].value.symbol, "+"));
    try testing.expect(std.mem.eql(u8, last_item.value.list.items[1].value.symbol, "x"));
    try testing.expect(std.mem.eql(u8, last_item.value.list.items[2].value.symbol, "y"));
}
