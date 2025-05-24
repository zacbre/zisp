const std = @import("std");
const testing = std.testing;

// LISP -> Lexer -> AST(Parser) -> Machine

pub const TokenKind = enum {
    LPAREN,
    RPAREN,
    QUOTE,

    // Identifiers and literals
    IDENTIFIER,
    NUMBER,
    STRING,
    BOOLEAN,

    // End of file
    ILLEGAL,
    EOF,
};

pub const Token = struct {
    kind: TokenKind,
    value: []const u8,
};

pub const Lexer = struct {
    input: []const u8,
    pos: usize,
    current: Token,

    pub fn init(input: []const u8) Lexer {
        return Lexer{
            .input = input,
            .pos = 0,
            .current = Token{ .kind = TokenKind.EOF, .value = "" },
        };
    }

    pub fn next_token(self: *Lexer) Token {
        // get the next token
        // first eat whitespace.
        self.skip_whitespace();
        if (self.pos >= self.input.len) {
            return Token{ .kind = TokenKind.EOF, .value = "" };
        }
        const ch = self.input[self.pos];
        switch (ch) {
            '\'' => {
                // call next_token() again to get the output, then add that to the token?
                self.pos += 1;
                self.current = Token{ .kind = TokenKind.QUOTE, .value = "'" };
            },
            '(' => {
                self.current = Token{ .kind = TokenKind.LPAREN, .value = "(" };
                self.pos += 1;
            },
            ')' => {
                self.current = Token{ .kind = TokenKind.RPAREN, .value = ")" };
                self.pos += 1;
            },
            '+' => {
                self.current = Token{ .kind = TokenKind.IDENTIFIER, .value = "+" };
                self.pos += 1;
            },
            '-' => {
                self.current = Token{ .kind = TokenKind.IDENTIFIER, .value = "-" };
                self.pos += 1;
            },
            '*' => {
                self.current = Token{ .kind = TokenKind.IDENTIFIER, .value = "*" };
                self.pos += 1;
            },
            '/' => {
                self.current = Token{ .kind = TokenKind.IDENTIFIER, .value = "/" };
                self.pos += 1;
            },
            '"' => {
                // parse a string literal
                const start = self.pos;
                self.pos += 1; // skip the opening quote
                while (self.pos < self.input.len and self.input[self.pos] != '"') {
                    self.pos += 1;
                }
                if (self.pos < self.input.len) {
                    self.pos += 1; // skip the closing quote
                }
                self.current = Token{ .kind = TokenKind.STRING, .value = self.input[start + 1 .. self.pos - 1] };
            },
            else => {
                if (ch >= '0' and ch <= '9' or ch == '.') {
                    // parse a number
                    const start = self.pos;
                    while (self.pos < self.input.len and self.input[self.pos] >= '0' and self.input[self.pos] <= '9') {
                        self.pos += 1;
                    }
                    if (self.pos < self.input.len and self.input[self.pos] == '.') {
                        self.pos += 1;
                        while (self.pos < self.input.len and self.input[self.pos] >= '0' and self.input[self.pos] <= '9') {
                            self.pos += 1;
                        }
                    }
                    self.current = Token{ .kind = TokenKind.NUMBER, .value = self.input[start..self.pos] };
                } else if ((ch >= 'a' and ch <= 'z') or ch == '_' or ch == '-') {
                    // parse an identifier
                    const start = self.pos;
                    while (self.pos < self.input.len and (self.input[self.pos] >= 'a' and self.input[self.pos] <= 'z' or self.input[self.pos] == '_' or self.input[self.pos] == '-')) {
                        self.pos += 1;
                    }
                    self.current = Token{ .kind = TokenKind.IDENTIFIER, .value = self.input[start..self.pos] };
                } else {
                    self.current = Token{ .kind = TokenKind.ILLEGAL, .value = "" };
                }
            },
        }
        return self.current;
    }

    fn skip_whitespace(self: *Lexer) void {
        while (self.pos < self.input.len) {
            const ch = self.input[self.pos];
            if (ch == ' ' or ch == '\n' or ch == '\r' or ch == '\t') {
                self.pos += 1;
            } else {
                break;
            }
        }
    }
};

test "can parse a number" {
    var lexer = Lexer.init("123");
    const token = lexer.next_token();
    try testing.expect(token.kind == TokenKind.NUMBER);
    try testing.expect(std.mem.eql(u8, token.value, "123"));
}

test "can parse a float" {
    var lexer = Lexer.init("123.456");
    const token = lexer.next_token();
    try testing.expect(token.kind == TokenKind.NUMBER);
    try testing.expect(std.mem.eql(u8, token.value, "123.456"));
}

test "can parse empty parens" {
    var lexer = Lexer.init("()");
    const token = lexer.next_token();
    try testing.expect(token.kind == TokenKind.LPAREN);
    try testing.expect(std.mem.eql(u8, token.value, "("));
    const token2 = lexer.next_token();
    try testing.expect(token2.kind == TokenKind.RPAREN);
    try testing.expect(std.mem.eql(u8, token2.value, ")"));
}

test "can skip whitespace and parse a number" {
    var lexer = Lexer.init("  123  ");
    const token = lexer.next_token();
    try testing.expect(token.kind == TokenKind.NUMBER);
    try testing.expect(std.mem.eql(u8, token.value, "123"));
}

test "can lex a simple expression" {
    var lexer = Lexer.init("(+ 1 2)");
    const token = lexer.next_token();
    try testing.expect(token.kind == TokenKind.LPAREN);
    try testing.expect(std.mem.eql(u8, token.value, "("));
    const token2 = lexer.next_token();
    try testing.expect(token2.kind == TokenKind.IDENTIFIER);
    try testing.expect(std.mem.eql(u8, token2.value, "+"));
    const token3 = lexer.next_token();
    try testing.expect(token3.kind == TokenKind.NUMBER);
    try testing.expect(std.mem.eql(u8, token3.value, "1"));
    const token4 = lexer.next_token();
    try testing.expect(token4.kind == TokenKind.NUMBER);
    try testing.expect(std.mem.eql(u8, token4.value, "2"));
    const token5 = lexer.next_token();
    try testing.expect(token5.kind == TokenKind.RPAREN);
    try testing.expect(std.mem.eql(u8, token5.value, ")"));
}

test "can lex a complex expression" {
    var lexer = Lexer.init("(+ (- 1 2) (* 3 4))");
    const token = lexer.next_token();
    try testing.expect(token.kind == TokenKind.LPAREN);
    try testing.expect(std.mem.eql(u8, token.value, "("));
    const token2 = lexer.next_token();
    try testing.expect(token2.kind == TokenKind.IDENTIFIER);
    try testing.expect(std.mem.eql(u8, token2.value, "+"));
    const token3 = lexer.next_token();
    try testing.expect(token3.kind == TokenKind.LPAREN);
    try testing.expect(std.mem.eql(u8, token3.value, "("));
    const token4 = lexer.next_token();
    try testing.expect(token4.kind == TokenKind.IDENTIFIER);
    try testing.expect(std.mem.eql(u8, token4.value, "-"));
    const token5 = lexer.next_token();
    try testing.expect(token5.kind == TokenKind.NUMBER);
    try testing.expect(std.mem.eql(u8, token5.value, "1"));
    const token6 = lexer.next_token();
    try testing.expect(token6.kind == TokenKind.NUMBER);
    try testing.expect(std.mem.eql(u8, token6.value, "2"));
    const token7 = lexer.next_token();
    try testing.expect(token7.kind == TokenKind.RPAREN);
    try testing.expect(std.mem.eql(u8, token7.value, ")"));
    const token8 = lexer.next_token();
    try testing.expect(token8.kind == TokenKind.LPAREN);
    try testing.expect(std.mem.eql(u8, token8.value, "("));
    const token9 = lexer.next_token();
    try testing.expect(token9.kind == TokenKind.IDENTIFIER);
    try testing.expect(std.mem.eql(u8, token9.value, "*"));
    const token10 = lexer.next_token();
    try testing.expect(token10.kind == TokenKind.NUMBER);
    try testing.expect(std.mem.eql(u8, token10.value, "3"));
    const token11 = lexer.next_token();
    try testing.expect(token11.kind == TokenKind.NUMBER);
    try testing.expect(std.mem.eql(u8, token11.value, "4"));
    const token12 = lexer.next_token();
    try testing.expect(token12.kind == TokenKind.RPAREN);
    try testing.expect(std.mem.eql(u8, token12.value, ")"));
    const token13 = lexer.next_token();
    try testing.expect(token13.kind == TokenKind.RPAREN);
    try testing.expect(std.mem.eql(u8, token13.value, ")"));
}

test "can parse identifier" {
    var lexer = Lexer.init("foo");
    const token = lexer.next_token();
    try testing.expect(token.kind == TokenKind.IDENTIFIER);
    try testing.expect(std.mem.eql(u8, token.value, "foo"));
}

test "can parse multiple identifiers" {
    var lexer = Lexer.init("(foo bar baz)");
    const token = lexer.next_token();
    try testing.expect(token.kind == TokenKind.LPAREN);
    try testing.expect(std.mem.eql(u8, token.value, "("));
    const token2 = lexer.next_token();
    try testing.expect(token2.kind == TokenKind.IDENTIFIER);
    try testing.expect(std.mem.eql(u8, token2.value, "foo"));
    const token3 = lexer.next_token();
    try testing.expect(token3.kind == TokenKind.IDENTIFIER);
    try testing.expect(std.mem.eql(u8, token3.value, "bar"));
    const token4 = lexer.next_token();
    try testing.expect(token4.kind == TokenKind.IDENTIFIER);
    try testing.expect(std.mem.eql(u8, token4.value, "baz"));
    const token5 = lexer.next_token();
    try testing.expect(token5.kind == TokenKind.RPAREN);
    try testing.expect(std.mem.eql(u8, token5.value, ")"));
}

test "can parse a string" {
    var lexer = Lexer.init("\"hello\"");
    const token = lexer.next_token();
    try testing.expect(token.kind == TokenKind.STRING);
    try testing.expect(std.mem.eql(u8, token.value, "hello"));
}

test "can parse a string with spaces" {
    var lexer = Lexer.init("\"hello world\"");
    const token = lexer.next_token();
    try testing.expect(token.kind == TokenKind.STRING);
    try testing.expect(std.mem.eql(u8, token.value, "hello world"));
}

test "can parse multiple strings" {
    var lexer = Lexer.init("(\"hello\" \"world\")");
    const token = lexer.next_token();
    try testing.expect(token.kind == TokenKind.LPAREN);
    try testing.expect(std.mem.eql(u8, token.value, "("));
    const token2 = lexer.next_token();
    try testing.expect(token2.kind == TokenKind.STRING);
    try testing.expect(std.mem.eql(u8, token2.value, "hello"));
    const token3 = lexer.next_token();
    try testing.expect(token3.kind == TokenKind.STRING);
    try testing.expect(std.mem.eql(u8, token3.value, "world"));
    const token4 = lexer.next_token();
    try testing.expect(token4.kind == TokenKind.RPAREN);
    try testing.expect(std.mem.eql(u8, token4.value, ")"));
}

test "can parse a non evaled expression" {
    var lexer = Lexer.init("'(1 2 3)");
    const token = lexer.next_token();
    try testing.expect(token.kind == TokenKind.QUOTE);
    try testing.expect(std.mem.eql(u8, token.value, "'"));
    const token2 = lexer.next_token();
    try testing.expect(token2.kind == TokenKind.LPAREN);
    try testing.expect(std.mem.eql(u8, token2.value, "("));
    const token3 = lexer.next_token();
    try testing.expect(token3.kind == TokenKind.NUMBER);
    try testing.expect(std.mem.eql(u8, token3.value, "1"));
    const token4 = lexer.next_token();
    try testing.expect(token4.kind == TokenKind.NUMBER);
    try testing.expect(std.mem.eql(u8, token4.value, "2"));
    const token5 = lexer.next_token();
    try testing.expect(token5.kind == TokenKind.NUMBER);
    try testing.expect(std.mem.eql(u8, token5.value, "3"));
    const token6 = lexer.next_token();
    try testing.expect(token6.kind == TokenKind.RPAREN);
    try testing.expect(std.mem.eql(u8, token6.value, ")"));
}
