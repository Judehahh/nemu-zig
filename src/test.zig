const std = @import("std");
const common = @import("common.zig");
const expr = @import("monitor/expr.zig");
const isa = @import("isa/riscv32.zig");

const expect = std.testing.expect;
const copyForwards = std.mem.copyForwards;

// Unit tests for expr() function
test "expr test" {
    // Init regex before test.
    expr.init_regex();
    defer expr.deinit_regex();

    // Init memory and pc.
    isa.init_isa();

    var result: common.word_t = undefined;

    // TokenType.NoType
    var tokens = std.mem.tokenize(u8, "  \t  123 \t", " \t");
    result = try expr.expr(&tokens);
    try expect(result == 123);
    // TokenType.Equal
    tokens = std.mem.tokenize(u8, "123 == 123", " \t");
    result = try expr.expr(&tokens);
    try expect(result == 1);
    tokens = std.mem.tokenize(u8, "123 == 321", " \t");
    result = try expr.expr(&tokens);
    try expect(result == 0);

    // TokenType.NotEqual
    tokens = std.mem.tokenize(u8, "123 != 123", " \t");
    result = try expr.expr(&tokens);
    try expect(result == 0);
    tokens = std.mem.tokenize(u8, "123 != 321", " \t");
    result = try expr.expr(&tokens);
    try expect(result == 1);

    // TokenType.And
    tokens = std.mem.tokenize(u8, "1 && 2", " \t");
    result = try expr.expr(&tokens);
    try expect(result == 1);
    tokens = std.mem.tokenize(u8, "0 && 2", " \t");
    result = try expr.expr(&tokens);
    try expect(result == 0);
    tokens = std.mem.tokenize(u8, "0 && 0", " \t");
    result = try expr.expr(&tokens);
    try expect(result == 0);

    // TokenType.Or
    tokens = std.mem.tokenize(u8, "1 || 2", " \t");
    result = try expr.expr(&tokens);
    try expect(result == 1);
    tokens = std.mem.tokenize(u8, "0 || -2", " \t");
    result = try expr.expr(&tokens);
    try expect(result == 1);
    tokens = std.mem.tokenize(u8, "0 || 0", " \t");
    result = try expr.expr(&tokens);
    try expect(result == 0);

    // TokenType.Hex
    tokens = std.mem.tokenize(u8, "0x80000000", " \t");
    result = try expr.expr(&tokens);
    try expect(result == 0x80000000);

    // TokenType.Dec
    tokens = std.mem.tokenize(u8, "12345678", " \t");
    result = try expr.expr(&tokens);
    try expect(result == 12345678);

    // TokenType.Plus
    tokens = std.mem.tokenize(u8, "123 + 123", " \t");
    result = try expr.expr(&tokens);
    try expect(result == 246);
    // FIXME: What to do if integer overflow
    // tokens = std.mem.tokenize(u8, "0xffffffff + 1", " \t");
    // result = try expr.expr(&tokens);
    // FIXME: What to do if val is negative
    // tokens = std.mem.tokenize(u8, "123 + -122", " \t");
    // result = try expr.expr(&tokens);

    // TokenType.Minus
    tokens = std.mem.tokenize(u8, "222 - 111", " \t");
    result = try expr.expr(&tokens);
    try expect(@as(i32, @bitCast(result)) == 111);
    tokens = std.mem.tokenize(u8, "666 - 777", " \t");
    result = try expr.expr(&tokens);
    try expect(@as(i32, @bitCast(result)) == -111);

    // TokenType.Mul
    tokens = std.mem.tokenize(u8, "0 * 0x12345678", " \t");
    result = try expr.expr(&tokens);
    try expect(@as(i32, @bitCast(result)) == 0);
    tokens = std.mem.tokenize(u8, "123 * 456", " \t");
    result = try expr.expr(&tokens);
    try expect(@as(i32, @bitCast(result)) == 56088);

    // TokenType.Div
    tokens = std.mem.tokenize(u8, "0 / 123", " \t");
    result = try expr.expr(&tokens);
    try expect(@as(i32, @bitCast(result)) == 0);
    tokens = std.mem.tokenize(u8, "246 / 123", " \t");
    result = try expr.expr(&tokens);
    try expect(@as(i32, @bitCast(result)) == 2);
    // ExprError.DivZero
    tokens = std.mem.tokenize(u8, "123 / 0", " \t");
    _ = expr.expr(&tokens) catch |err| {
        try expect(err == expr.ExprError.DivZero);
    };

    // TokenType.LeftParen
    // TokenType.RightParen
    tokens = std.mem.tokenize(u8, "(123)", " \t");
    result = try expr.expr(&tokens);
    try expect(@as(i32, @bitCast(result)) == 123);

    // TokenType.Reg
    tokens = std.mem.tokenize(u8, "$pc", " \t");
    result = try expr.expr(&tokens);
    try expect(result == 0x80000000);

    // TokenType.Ref
    tokens = std.mem.tokenize(u8, "*$pc", " \t");
    result = try expr.expr(&tokens);
    try expect(result == 0x00000297);
    tokens = std.mem.tokenize(u8, "*0x80000010", " \t");
    result = try expr.expr(&tokens);
    try expect(result == 0xdeadbeef);
    tokens = std.mem.tokenize(u8, "2**0x80000000", " \t");
    result = try expr.expr(&tokens);
    try expect(result == 0x0000052e);

    // TokenType.Neg
    tokens = std.mem.tokenize(u8, "-1", " \t");
    result = try expr.expr(&tokens);
    try expect(@as(i32, @bitCast(result)) == -1);
    tokens = std.mem.tokenize(u8, "--123", " \t");
    result = try expr.expr(&tokens);
    try expect(@as(i32, @bitCast(result)) == 123);
    // FIXME: this will cause integer overflow, because '-123' will be casted to word_t(unsigned).
    // tokens = std.mem.tokenize(u8, "125 + -123", " \t");
    // result = try expr.expr(&tokens);
    // try expect(@as(i32, @bitCast(result)) == 2);

    // ExprError.NoInput
    // tokens = std.mem.tokenize(u8, &([1]u8{0} ** 32), " \t");
    // _ = expr.expr(&tokens) catch |err| {
    // try expect(err == expr.ExprError.NoInput);
    // };
    tokens = std.mem.tokenize(u8, " \t \t\t   ", " \t");
    _ = expr.expr(&tokens) catch |err| {
        try expect(err == expr.ExprError.NoInput);
    };

    // ExprError.TokenNoMatch
    tokens = std.mem.tokenize(u8, "@#$", " \t");
    _ = expr.expr(&tokens) catch |err| {
        try expect(err == expr.ExprError.TokenNoMatch);
    };

    // ExprError.BadExpr
    tokens = std.mem.tokenize(u8, "*", " \t");
    _ = expr.expr(&tokens) catch |err| {
        try expect(err == expr.ExprError.BadExpr);
    };

    // ExprError.PrinOpNotFound
    tokens = std.mem.tokenize(u8, "12 (34)", " \t");
    _ = expr.expr(&tokens) catch |err| {
        try expect(err == expr.ExprError.PrinOpNotFound);
    };

    // ExprError.ParenNotPair
    tokens = std.mem.tokenize(u8, "12 + ((34)", " \t");
    _ = expr.expr(&tokens) catch |err| {
        try expect(err == expr.ExprError.PrinOpNotFound);
    };
}
