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
    List: std.ArrayList(AstNode),
    String: []const u8,
    Boolean: bool,
    Quoted: *AstNode,
    Function: BuiltinFn,

    pub fn deinit(self: AstNode, allocator: *std.mem.Allocator) void {
        switch (self) {
            .List => |list| {
                for (list.items) |node| {
                    node.deinit(allocator);
                }
                list.deinit();
            },
            .Quoted => |quoted| {
                const inner = quoted.*;
                inner.deinit(allocator);
                allocator.destroy(quoted);
            },
            else => {},
        }
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
            .current_node = allocator.create(AstNode) catch @panic("OOM while creating AST node"),
            .node_stack = std.ArrayList(*AstNode).init(allocator),
        };
        p.current_node.* = AstNode{ .List = std.ArrayList(AstNode).init(allocator) };
        p.next_token();
        return p;
    }

    pub fn parse_single(self: *Parser) !AstNode {
        const node = try self.parse();
        defer node.deinit(&self.allocator);
        return node.List.items[0];
    }

    pub fn parse(self: *Parser) !*AstNode {
        while (true) {
            switch (self.current_token.kind) {
                TokenKind.LPAREN => {
                    self.next_token();
                    try self.node_stack.append(self.current_node);
                    // make a new list node
                    const list = try self.allocator.create(AstNode);
                    list.* = AstNode{ .List = std.ArrayList(AstNode).init(self.allocator) };
                    self.current_node = list;
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
                    try self.current_node.List.append(old_node.*);
                },
                TokenKind.QUOTE => {
                    self.next_token();
                    const quoted = try self.parse();
                    const inner = try self.allocator.create(AstNode);
                    inner.* = quoted;
                    self.next_token();
                    self.current_node.List.append(AstNode{ .Quoted = inner }) catch {
                        std.debug.panic("Failed to append quoted node to list", .{});
                    };
                },
                TokenKind.NUMBER => {
                    const value = std.fmt.parseFloat(f64, self.current_token.value) catch {
                        std.debug.panic("Failed to parse float: {d}", .{self.current_token.value});
                    };
                    self.next_token();
                    self.current_node.List.append(AstNode{ .Number = value }) catch {
                        std.debug.panic("Failed to append number to list", .{});
                    };
                },
                TokenKind.IDENTIFIER => {
                    const value = self.current_token.value;
                    self.next_token();
                    self.current_node.List.append(AstNode{ .Symbol = value }) catch {
                        std.debug.panic("Failed to append symbol to list", .{});
                    };
                },
                TokenKind.STRING => {
                    const value = self.current_token.value;
                    self.next_token();
                    self.current_node.List.append(AstNode{ .String = value }) catch {
                        std.debug.panic("Failed to append string to list", .{});
                    };
                },
                TokenKind.BOOLEAN => {
                    const value = if (std.mem.eql(u8, self.current_token.value, "#t")) true else false;
                    self.next_token();
                    self.current_node.List.append(AstNode{ .Boolean = value }) catch {
                        std.debug.panic("Failed to append boolean to list", .{});
                    };
                },
                TokenKind.EOF => {
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
};

test "can parse a simple expression" {
    var allocator = std.testing.allocator;
    var parser = Parser.init("(+ 1 2)", allocator);
    const node = try parser.parse();
    defer node.deinit(&allocator);

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
    var allocator = std.testing.allocator;
    var parser = Parser.init("\"hello\"", allocator);
    const node = try parser.parse_single();
    defer node.deinit(&allocator);
    // get the first item from the list.
    try testing.expect(std.mem.eql(u8, node.String, "hello"));
}

test "can parse a boolean" {
    var allocator = std.testing.allocator;
    var parser = Parser.init("#t", allocator);
    const node = try parser.parse_single();
    defer node.deinit(&allocator);
    try testing.expect(node.Boolean == true);

    parser = Parser.init("#f", allocator);
    const node2 = try parser.parse_single();
    defer node2.deinit(&allocator);
    try testing.expect(node2.Boolean == false);
}
test "can parse a number" {
    var allocator = std.testing.allocator;
    var parser = Parser.init("42", allocator);
    const node = try parser.parse_single();
    defer node.deinit(&allocator);
    try testing.expect(node.Number == 42);
}

test "can parse an identifier" {
    var allocator = std.testing.allocator;
    var parser = Parser.init("foo", allocator);
    const node = try parser.parse_single();
    defer node.deinit(&allocator);
    try testing.expect(std.mem.eql(u8, node.Symbol, "foo"));
}

test "can parse a list with mixed types" {
    var allocator = std.testing.allocator;
    var parser = Parser.init("(foo 42 123.456 \"bar\" #t)", allocator);
    const node = try parser.parse();
    defer node.deinit(&allocator);
    try testing.expect(node.List.items.len == 5);
    try testing.expect(std.mem.eql(u8, node.List.items[0].Symbol, "foo"));
    try testing.expect(node.List.items[1].Number == 42);
    try testing.expect(std.math.approxEqAbs(f64, node.List.items[2].Number, 123.456, 0.0001));
    try testing.expect(std.mem.eql(u8, node.List.items[3].String, "bar"));
    try testing.expect(node.List.items[4].Boolean == true);
}

test "can parse nested expression" {
    var allocator = std.testing.allocator;
    var parser = Parser.init("(foo (bar 42) (baz 123))", allocator);
    const node = try parser.parse();
    defer node.deinit(&allocator);
    //try testing.expect(node.List.items.len == 3);
    try testing.expect(std.mem.eql(u8, node.List.items[0].Symbol, "foo"));
    try testing.expect(node.List.items[1].List.items.len == 2);
    try testing.expect(std.mem.eql(u8, node.List.items[1].List.items[0].Symbol, "bar"));
    try testing.expect(node.List.items[1].List.items[1].Number == 42);
    try testing.expect(node.List.items[2].List.items.len == 2);
    try testing.expect(std.mem.eql(u8, node.List.items[2].List.items[0].Symbol, "baz"));
    try testing.expect(node.List.items[2].List.items[1].Number == 123);
}
