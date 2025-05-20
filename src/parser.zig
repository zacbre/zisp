const lexer = @import("lexer.zig");
const std = @import("std");
const testing = std.testing;

const TokenKind = lexer.TokenKind;
const Token = lexer.Token;
const Lexer = lexer.Lexer;

const BuiltinFn = @import("builtin.zig").BuiltinFn;

pub const AstNode = union(enum) {
    Symbol: []const u8,
    Number: f64,
    List: std.ArrayList(*AstNode),
    String: []const u8,
    Boolean: bool,
    Quoted: *AstNode,
    Function: BuiltinFn,

    pub fn deinit(self: *AstNode, allocator: *std.mem.Allocator) void {
        switch (self.*) {
            .List => |list| {
                for (list.items) |node| {
                    node.deinit(allocator);
                }
                list.deinit();
            },
            .Quoted => |quoted| {
                quoted.deinit(allocator);
                allocator.destroy(quoted);
            },
            else => {},
        }
        allocator.destroy(self);
    }
};

pub const Parser = struct {
    allocator: std.mem.Allocator,
    lexer: Lexer,
    current_token: Token,
    current_node: *AstNode,
    node_stack: std.ArrayList(*AstNode),

    pub fn init(input: []const u8, allocator: std.mem.Allocator) Parser {
        var empty_node = AstNode{ .Number = 0 };
        var p = Parser{
            .lexer = Lexer.init(input),
            .allocator = allocator,
            .current_token = Token{ .kind = TokenKind.EOF, .value = "" },
            .current_node = &empty_node,
            .node_stack = std.ArrayList(*AstNode).init(allocator),
        };

        p.next_token();
        return p;
    }

    pub fn deinit(self: *Parser) void {
        self.current_node.deinit(&self.allocator);
    }

    pub fn parse(self: *Parser) !*AstNode {
        self.current_node = try self.make_node(AstNode{ .List = std.ArrayList(*AstNode).init(self.allocator) });
        defer self.node_stack.deinit();

        while (true) {
            switch (self.current_token.kind) {
                TokenKind.LPAREN => {
                    self.next_token();
                    try self.node_stack.append(self.current_node);
                    self.current_node = try self.make_node(AstNode{ .List = std.ArrayList(*AstNode).init(self.allocator) });
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
                    try self.current_node.List.append(old_node);
                },
                TokenKind.QUOTE => {
                    self.next_token();
                    const quoted = try self.parse();
                    const inner = try self.make_node(AstNode{ .Quoted = quoted });
                    self.next_token();
                    self.current_node.List.append(inner) catch {
                        std.debug.panic("Failed to append quoted node to list", .{});
                    };
                },
                TokenKind.NUMBER => {
                    const value = std.fmt.parseFloat(f64, self.current_token.value) catch {
                        std.debug.panic("Failed to parse float: {d}", .{self.current_token.value});
                    };
                    self.next_token();
                    try self.current_node.List.append(try self.make_node(AstNode{ .Number = value }));
                },
                TokenKind.IDENTIFIER => {
                    const value = self.current_token.value;
                    self.next_token();
                    try self.current_node.List.append(try self.make_node(AstNode{ .Symbol = value }));
                },
                TokenKind.STRING => {
                    const value = self.current_token.value;
                    self.next_token();
                    try self.current_node.List.append(try self.make_node(AstNode{ .String = value }));
                },
                TokenKind.BOOLEAN => {
                    const value = if (std.mem.eql(u8, self.current_token.value, "#t")) true else false;
                    self.next_token();
                    try self.current_node.List.append(try self.make_node(AstNode{ .Boolean = value }));
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

    fn make_node(self: *Parser, kind: AstNode) !*AstNode {
        const node = try self.allocator.create(AstNode);
        node.* = kind;
        return node;
    }
};

fn deref_list(node: *AstNode) AstNode {
    return node.*.List.items[0].*;
}

test "can parse a simple expression" {
    const allocator = std.testing.allocator;
    var parser = Parser.init("(+ 1 2)", allocator);
    defer parser.deinit();

    const output = try parser.parse();
    const node = deref_list(output);

    try testing.expect(node.List.items.len == 3);
    try testing.expect(std.mem.eql(u8, node.List.items[0].Symbol, "+"));
    try testing.expect(node.List.items[1].Number == 1);
    try testing.expect(node.List.items[2].Number == 2);
}

// test "can parse a quoted expression" {
//     var allocator = std.testing.allocator;
//     var parser = Parser.init("'(1 2)", allocator);
//     const node = try parser.parse();
//     defer node.deinit(&allocator);
//     try testing.expect(node.Quoted.*.List.items.len == 2);
//     try testing.expect(node.Quoted.*.List.items[0].Number == 1);
//     try testing.expect(node.Quoted.*.List.items[1].Number == 2);
// }

test "can parse a string" {
    const allocator = std.testing.allocator;
    var parser = Parser.init("\"hello\"", allocator);
    defer parser.deinit();

    const output = try parser.parse();
    const node = deref_list(output);

    // get the first item from the list.
    try testing.expect(std.mem.eql(u8, node.String, "hello"));
}

test "can parse a boolean" {
    const allocator = std.testing.allocator;
    var parser = Parser.init("#t", allocator);

    const output = try parser.parse();
    const node = deref_list(output);

    try testing.expect(node.Boolean == true);
    parser.deinit();

    parser = Parser.init("#f", allocator);
    const output2 = try parser.parse();
    const node2 = deref_list(output2);

    try testing.expect(node2.Boolean == false);
    parser.deinit();
}
test "can parse a number" {
    const allocator = std.testing.allocator;
    var parser = Parser.init("42", allocator);
    defer parser.deinit();
    const output = try parser.parse();
    const node = deref_list(output);
    try testing.expect(node.Number == 42);
}

test "can parse an identifier" {
    const allocator = std.testing.allocator;
    var parser = Parser.init("foo", allocator);
    defer parser.deinit();
    const output = try parser.parse();
    const node = deref_list(output);
    try testing.expect(std.mem.eql(u8, node.Symbol, "foo"));
}

test "can parse a list with mixed types" {
    const allocator = std.testing.allocator;
    var parser = Parser.init("(foo 42 123.456 \"bar\" #t)", allocator);
    defer parser.deinit();
    const output = try parser.parse();

    const node = deref_list(output);
    try testing.expect(node.List.items.len == 5);
    try testing.expect(std.mem.eql(u8, node.List.items[0].Symbol, "foo"));
    try testing.expect(node.List.items[1].Number == 42);
    try testing.expect(std.math.approxEqAbs(f64, node.List.items[2].Number, 123.456, 0.0001));
    try testing.expect(std.mem.eql(u8, node.List.items[3].String, "bar"));
    try testing.expect(node.List.items[4].Boolean == true);
}

test "can parse nested expression" {
    const allocator = std.testing.allocator;
    var parser = Parser.init("(foo (bar 42) (baz 123))", allocator);
    defer parser.deinit();

    const output = try parser.parse();
    const node = deref_list(output);
    //try testing.expect(node.List.items.len == 3);
    try testing.expect(std.mem.eql(u8, node.List.items[0].Symbol, "foo"));
    try testing.expect(node.List.items[1].List.items.len == 2);
    try testing.expect(std.mem.eql(u8, node.List.items[1].List.items[0].Symbol, "bar"));
    try testing.expect(node.List.items[1].List.items[1].Number == 42);
    try testing.expect(node.List.items[2].List.items.len == 2);
    try testing.expect(std.mem.eql(u8, node.List.items[2].List.items[0].Symbol, "baz"));
    try testing.expect(node.List.items[2].List.items[1].Number == 123);
}
