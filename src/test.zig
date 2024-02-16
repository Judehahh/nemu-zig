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
    result = try expr.expr("  \t  123 \t");
    try expect(result == 123);
    // TokenType.Equal
    result = try expr.expr("123 == 123");
    try expect(result == 1);
    result = try expr.expr("123 == 321");
    try expect(result == 0);

    // TokenType.NotEqual
    result = try expr.expr("123 != 123");
    try expect(result == 0);
    result = try expr.expr("123 != 321");
    try expect(result == 1);

    // TokenType.And
    result = try expr.expr("1 && 2");
    try expect(result == 1);
    result = try expr.expr("0 && 2");
    try expect(result == 0);
    result = try expr.expr("0 && 0");
    try expect(result == 0);

    // TokenType.Or
    result = try expr.expr("1 || 2");
    try expect(result == 1);
    result = try expr.expr("0 || -2");
    try expect(result == 1);
    result = try expr.expr("0 || 0");
    try expect(result == 0);

    // TokenType.Hex
    result = try expr.expr("0x80000000");
    try expect(result == 0x80000000);

    // TokenType.Dec
    result = try expr.expr("12345678");
    try expect(result == 12345678);

    // TokenType.Plus
    result = try expr.expr("123 + 123");
    try expect(result == 246);
    // FIXME: What to do if integer overflow
    // result = try expr.expr("0xffffffff + 1");
    // FIXME: What to do if val is negative
    // result = try expr.expr("123 + -122");

    // TokenType.Minus
    result = try expr.expr("222 - 111");
    try expect(@as(i32, @bitCast(result)) == 111);
    result = try expr.expr("666 - 777");
    try expect(@as(i32, @bitCast(result)) == -111);

    // TokenType.Mul
    result = try expr.expr("0 * 0x12345678");
    try expect(@as(i32, @bitCast(result)) == 0);
    result = try expr.expr("123 * 456");
    try expect(@as(i32, @bitCast(result)) == 56088);

    // TokenType.Div
    result = try expr.expr("0 / 123");
    try expect(@as(i32, @bitCast(result)) == 0);
    result = try expr.expr("246 / 123");
    try expect(@as(i32, @bitCast(result)) == 2);
    // ExprError.DivZero
    _ = expr.expr("123 / 0") catch |err| {
        try expect(err == expr.ExprError.DivZero);
    };

    // TokenType.LeftParen
    // TokenType.RightParen
    result = try expr.expr("(123)");
    try expect(@as(i32, @bitCast(result)) == 123);

    // TokenType.Reg
    result = try expr.expr("$pc");
    try expect(result == 0x80000000);

    // TokenType.Ref
    result = try expr.expr("*$pc");
    try expect(result == 0x00000297);
    result = try expr.expr("*0x80000010");
    try expect(result == 0xdeadbeef);
    result = try expr.expr("2**0x80000000");
    try expect(result == 0x0000052e);

    // TokenType.Neg
    result = try expr.expr("-1");
    try expect(@as(i32, @bitCast(result)) == -1);
    result = try expr.expr("--123");
    try expect(@as(i32, @bitCast(result)) == 123);
    // FIXME: this will cause integer overflow, because '-123' will be casted to word_t(unsigned).
    // result = try expr.expr("125 + -123");
    // try expect(@as(i32, @bitCast(result)) == 2);

    // ExprError.NoInput
    _ = expr.expr("") catch |err| {
        try expect(err == expr.ExprError.NoInput);
    };
    _ = expr.expr(" \t \t\t   ") catch |err| {
        try expect(err == expr.ExprError.NoInput);
    };

    // ExprError.TokenNoMatch
    _ = expr.expr("@#$") catch |err| {
        try expect(err == expr.ExprError.TokenNoMatch);
    };

    // ExprError.BadExpr
    _ = expr.expr("*") catch |err| {
        try expect(err == expr.ExprError.BadExpr);
    };

    // ExprError.PrinOpNotFound
    _ = expr.expr("12 (34)") catch |err| {
        try expect(err == expr.ExprError.PrinOpNotFound);
    };

    // ExprError.ParenNotPair
    _ = expr.expr("(1234))") catch |err| {
        try expect(err == expr.ExprError.ParenNotPair);
    };
}
