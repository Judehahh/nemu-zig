const std = @import("std");
const util = @import("../util.zig");
const common = @import("../common.zig");
const c = @cImport({
    @cInclude("regex.h");
    @cInclude("regex_slim.h");
});

const TokenType = enum {
    NoType,
    Equal,
    Hex,
    Dec,
    Plus,
    Minus,
    Mul,
    Div,
    LeftParen,
    RightParen,
    // TODO: Reg, Ref, Neg...
};

// Regex compile rules.
const rules = [_]struct {
    regex: [:0]const u8,
    token_type: TokenType,
}{
    .{ .regex = " +", .token_type = TokenType.NoType }, // spaces
    .{ .regex = "==", .token_type = TokenType.Equal }, // equal
    .{ .regex = "0x[a-fA-F0-9]+", .token_type = TokenType.Hex }, // hexadecimal, must place before decimal
    .{ .regex = "[0-9]+", .token_type = TokenType.Dec }, // decimal
    .{ .regex = "\\+", .token_type = TokenType.Plus }, // plus
    .{ .regex = "\\-", .token_type = TokenType.Minus }, // minus
    .{ .regex = "\\*", .token_type = TokenType.Mul }, // multiplication
    .{ .regex = "\\/", .token_type = TokenType.Div }, // division
    .{ .regex = "\\(", .token_type = TokenType.LeftParen }, // left parenthesis
    .{ .regex = "\\)", .token_type = TokenType.RightParen }, // right parenthesis
};

// A buffer to store tokens for the current expression.
const max_tokens = 32;
var tokens: [max_tokens]struct {
    type: TokenType = undefined,
    str: [32]u8 = .{0} ** 32,
} = undefined;
var nr_token: usize = 0;

// Regex type to handling regular expression.
// One Regex value for each regex rules.
const Regex = struct {
    inner: *c.regex_t,
    type: TokenType,

    fn init(pattern: [:0]const u8, token_type: TokenType) Regex {
        const inner = c.alloc_regex_t().?;
        const ret = c.regcomp(inner, pattern, c.REG_EXTENDED);
        if (ret != 0) {
            var error_msg: [128:0]u8 = undefined;
            _ = c.regerror(ret, inner, &error_msg, 128);
            util.panic("regex \"{s}\" compilation failed: {s}.", .{ pattern, error_msg });
        }

        return .{
            .inner = inner,
            .type = token_type,
        };
    }

    fn deinit(self: Regex) void {
        c.free_regex_t(self.inner);
    }

    fn match(self: Regex, e: []const u8, position: *usize) bool {
        var pmatch: c.regmatch_t = undefined;
        if (c.regexec(self.inner, e[position.*..].ptr, 1, &pmatch, 0) == 0 and pmatch.rm_so == 0) {
            const substr = e[position.* .. position.* + @as(usize, @intCast(pmatch.rm_eo))];

            // util.log(@src(), "match token at position {d} with len {d}: {s}\n", .{ position.*, substr.len, substr });

            position.* += substr.len;

            switch (self.type) {
                .NoType => {},
                .Hex, .Dec => {
                    std.mem.copyForwards(u8, &tokens[nr_token].str, substr);
                    tokens[nr_token].str[substr.len] = 0;
                    tokens[nr_token].type = self.type;
                    nr_token += 1;
                },
                else => {
                    tokens[nr_token].type = self.type;
                    nr_token += 1;
                },
            }
            return true;
        }
        return false;
    }
};

// To store Regex type members.
var re: [rules.len]Regex = undefined;

/// Regex has to init when the monitor startup.
/// This will compile the regex rules.
pub fn init_regex() void {
    inline for (&re, 0..) |*r, i| {
        r.* = Regex.init(rules[i].regex, rules[i].token_type);
    }
}

/// Regex should return the memory when the monitor exit.
pub fn deinit_regex() void {
    inline for (re) |r| {
        r.deinit();
    }
}

/// Receive an expression and return the value of the expression.
pub fn expr(e: []const u8) !common.word_t {
    try make_token(e);
    if (nr_token == 0) return error.NoInput;

    // TODO: Reg, Ref, Neg...

    return try eval(0, nr_token - 1);
}

fn make_token(e: []const u8) anyerror!void {
    var position: usize = 0;

    nr_token = 0;

    while (e[position] != 0) {
        for (re) |r| {
            if (r.match(e, &position) == true)
                break;
        } else {
            std.debug.print("no match at position {d}.\n{s}\n{s: >[3]}^\n", .{ position, e, "", position });
            return error.NoMatch;
        }
    }
}

// A recursive function that evaluates a tokenized expression.
fn eval(p: usize, q: usize) !common.word_t {
    // Bad expression.
    if (p > q) return error.BadExpr;

    // Only one token left.
    if (p == q) {
        var value: common.word_t = undefined;
        switch (tokens[p].type) {
            TokenType.Hex => {
                value = try std.fmt.parseInt(common.word_t, std.mem.sliceTo(&tokens[p].str, 0)[2..], 16); // [2..] to skip "0x"
            },
            TokenType.Dec => {
                value = try std.fmt.parseInt(common.word_t, std.mem.sliceTo(&tokens[p].str, 0), 10);
            },
            else => std.debug.assert(false),
        }
        return value;
    }

    // Exactly surrounded by parentheses.
    if (tokens[p].type == TokenType.LeftParen and tokens[q].type == TokenType.RightParen) {
        return try eval(p + 1, q - 1);
    }

    // Else.
    const op = try get_principal_op(p, q);
    const op_type = tokens[op].type;
    if (op == 0) return error.BadExpr;

    // TODO: Reg, Ref, Neg...

    const lval: common.word_t = try eval(p, op - 1);
    const rval: common.word_t = try eval(op + 1, q);

    switch (op_type) {
        .Mul => return lval * rval,
        .Div => {
            if (rval == 0) return error.DivZero;
            return lval / rval;
        },
        .Plus => return lval + rval,
        .Minus => {
            if (lval < rval) return error.NotSupportNeg;
            return lval - rval;
        },
        .Equal => return @intFromBool(lval == rval),
        else => std.debug.assert(false),
    }

    unreachable;
}

// Get the main/principal op (the highest priority op) in a expression.
fn get_principal_op(p: usize, q: usize) anyerror!usize {
    var principal_op: usize = max_tokens;
    var baren_count: i8 = 0;

    for (p..q + 1) |i| {
        switch (tokens[i].type) {
            .Hex, .Dec => {},
            .LeftParen => {
                baren_count += 1;
            },
            .RightParen => {
                baren_count -= 1;
                if (baren_count < 0) {
                    return error.ParenNotPair;
                }
            },
            else => {
                if (principal_op == max_tokens or op_priority(tokens[i].type) < op_priority(tokens[principal_op].type)) {
                    principal_op = i;
                }
            },
        }
    }

    if (principal_op == max_tokens) return error.PrinOpNotFound;
    return principal_op;
}

// Get the priority of an op.
fn op_priority(t: TokenType) u8 {
    switch (t) {
        // Small numbers represent high priority.
        .Mul, .Div => return 0,
        .Plus, .Minus => return 1,
        .Equal => return 2,
        else => std.debug.assert(false),
    }
    unreachable;
}
