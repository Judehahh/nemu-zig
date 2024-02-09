const std = @import("std");
const util = @import("../util.zig");
const common = @import("../common.zig");
const isa = @import("../isa/riscv32.zig");
const memory = @import("../memory.zig");

// Import c for regex.
const c = @cImport({
    @cInclude("regex.h");
    @cInclude("regex_slim.h");
});

pub const ExprError = error{
    NoInput,
    TokenNoMatch,
    BadExpr,
    DivZero,
    ParenNotPair,
    PrinOpNotFound,
};

const TokenType = enum {
    NoType,
    Equal,
    NotEqual,
    And,
    Or,
    Hex,
    Dec,
    Plus,
    Minus,
    Mul,
    Div,
    LeftParen,
    RightParen,
    Reg,
    Ref,
    Neg,
};

// Regex compile rules.
const rules = [_]struct {
    regex: [:0]const u8,
    token_type: TokenType,
}{
    .{ .regex = " +", .token_type = TokenType.NoType }, // spaces
    .{ .regex = "\t+", .token_type = TokenType.NoType }, // tab
    .{ .regex = "==", .token_type = TokenType.Equal }, // equal
    .{ .regex = "!=", .token_type = TokenType.NotEqual }, // not equal
    .{ .regex = "\\&\\&", .token_type = TokenType.And }, // and
    .{ .regex = "\\|\\|", .token_type = TokenType.Or }, // or
    .{ .regex = "0x[a-fA-F0-9]+", .token_type = TokenType.Hex }, // hexadecimal, must place before decimal
    .{ .regex = "[0-9]+", .token_type = TokenType.Dec }, // decimal
    .{ .regex = "\\+", .token_type = TokenType.Plus }, // plus
    .{ .regex = "\\-", .token_type = TokenType.Minus }, // minus
    .{ .regex = "\\*", .token_type = TokenType.Mul }, // multiplication
    .{ .regex = "\\/", .token_type = TokenType.Div }, // division
    .{ .regex = "\\(", .token_type = TokenType.LeftParen }, // left parenthesis
    .{ .regex = "\\)", .token_type = TokenType.RightParen }, // right parenthesis
    .{ .regex = "\\$[a-z][a-z0-9]", .token_type = TokenType.Reg }, // register
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
                .Hex, .Dec, .Reg => {
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
pub fn expr(args_tokens: *std.mem.TokenIterator(u8, .any)) !common.word_t {
    nr_token = 0;
    while (args_tokens.next()) |arg_token| {
        try make_token(arg_token);
    }
    if (nr_token == 0) return ExprError.NoInput;

    // If token '-'/'*' is the first one
    // or the previous token is not ')' or a value.
    // The token '-'/'*' should means negative/dereference.
    var prev_type: TokenType = undefined;
    for (&tokens, 0..) |*token, i| {
        if (token.type == .Minus) {
            if (i == 0) {
                token.*.type = .Neg;
                continue;
            }
            prev_type = tokens[i - 1].type;
            if (prev_type != .RightParen and
                prev_type != .Hex and
                prev_type != .Dec and
                prev_type != .Reg)
            {
                token.*.type = .Neg;
            }
        } else if (token.type == .Mul) {
            if (i == 0) {
                token.*.type = .Ref;
                continue;
            }
            prev_type = tokens[i - 1].type;
            if (prev_type != .RightParen and
                prev_type != .Hex and
                prev_type != .Dec and
                prev_type != .Reg)
            {
                token.*.type = .Ref;
            }
        }
    }

    return try eval(0, nr_token - 1);
}

fn make_token(e: []const u8) !void {
    var position: usize = 0;

    while (position < e.len) {
        for (re) |r| {
            if (r.match(e, &position) == true)
                break;
        } else {
            std.debug.print("no match at position {d}.\n{s}\n{s: >[3]}^\n", .{ position, e, "", position });
            return ExprError.TokenNoMatch;
        }
    }
}

// A recursive function that evaluates a tokenized expression.
fn eval(p: usize, q: usize) !common.word_t {
    // Bad expression.
    if (p > q) return ExprError.BadExpr;

    // Only one token left.
    if (p == q) {
        return switch (tokens[p].type) {
            .Hex => try std.fmt.parseInt(common.word_t, std.mem.sliceTo(&tokens[p].str, 0)[2..], 16), // [2..] to skip "0x"
            .Dec => try std.fmt.parseInt(common.word_t, std.mem.sliceTo(&tokens[p].str, 0), 10),
            .Reg => try isa.isa_reg_name2val(std.mem.sliceTo(&tokens[p].str, 0)[1..]), // [1..] to skip "$"
            else => return ExprError.BadExpr,
        };
    }

    // Exactly surrounded by parentheses.
    if (tokens[p].type == TokenType.LeftParen and tokens[q].type == TokenType.RightParen) {
        return try eval(p + 1, q - 1);
    }

    // Else.
    const op = try get_principal_op(p, q);
    const op_type = tokens[op].type;

    if (op == 0 or op_type == .Neg or op_type == .Ref) {
        const val: common.word_t = try eval(op + 1, q);

        switch (op_type) {
            .Neg => return @bitCast(-@as(i32, @bitCast(val))),
            .Ref => return memory.vaddr_read_safe(val, 4) catch |err| {
                switch (err) {
                    memory.MemError.OutOfBound => std.debug.print("Cannot access memory at address " ++ common.fmt_word ++ ".\n", .{val}),
                    memory.MemError.NotAlign => std.debug.print("Address " ++ common.fmt_word ++ " is not aligned to 4 bytes.\n", .{val}),
                    else => unreachable,
                }
                return err;
            },
            else => {},
        }
    }

    const lval: common.word_t = try eval(p, op - 1);
    const rval: common.word_t = try eval(op + 1, q);

    return switch (op_type) {
        // FIXME: What to do if integer overflow
        // FIXME: What to do if val is negative
        .Mul => lval * rval,
        .Div => if (rval != 0) lval / rval else ExprError.DivZero,
        .Plus => lval + rval,
        .Minus => if (lval >= rval) lval - rval else @bitCast(@as(i32, @bitCast(lval)) - @as(i32, @bitCast(rval))),

        .Equal => @intFromBool(lval == rval),
        .NotEqual => @intFromBool(lval != rval),
        .And => @intFromBool(lval > 0 and rval > 0),
        .Or => @intFromBool(lval > 0 or rval > 0),

        else => unreachable,
    };
}

// Get the main/principal op (the lowest priority op) in a expression.
fn get_principal_op(p: usize, q: usize) !usize {
    var principal_op: usize = max_tokens;
    var baren_count: i8 = 0;

    for (p..q + 1) |i| {
        switch (tokens[i].type) {
            .Hex, .Dec, .Reg => {},
            .LeftParen => baren_count += 1,
            .RightParen => {
                baren_count -= 1;
                if (baren_count < 0) {
                    return ExprError.ParenNotPair;
                }
            },
            else => {
                if (baren_count == 0 and
                    principal_op == max_tokens or
                    op_priority(tokens[i].type) > op_priority(tokens[principal_op].type) or
                    (op_priority(tokens[i].type) == op_priority(tokens[principal_op].type) and
                    tokens[i].type != .Ref and
                    tokens[i].type != .Neg))
                {
                    principal_op = i;
                }
            },
        }
    }

    if (principal_op == max_tokens) return ExprError.PrinOpNotFound;
    return principal_op;
}

// Get the priority of an op.
fn op_priority(t: TokenType) u8 {
    switch (t) {
        // Small numbers represent high priority.
        .Neg, .Ref => return 0,
        .Mul, .Div => return 1,
        .Plus, .Minus => return 2,
        .Equal, .NotEqual => return 3,
        .And => return 4,
        .Or => return 5,
        else => unreachable,
    }
}
