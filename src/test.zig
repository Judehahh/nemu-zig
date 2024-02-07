const std = @import("std");
const common = @import("common.zig");
const expr = @import("monitor/expr.zig");
const isa = @import("isa/riscv32.zig");

const expect = std.testing.expect;
const copyForwards = std.mem.copyForwards;

inline fn copyWithZeroEnd(comptime T: type, dest: []T, source: []const T) void {
    copyForwards(T, dest, source ++ [1]u8{0});
}

// Unit tests for expr() function
test "expr test" {
    // Init regex before test.
    expr.init_regex();
    defer expr.deinit_regex();

    // Init memory and pc.
    isa.init_isa();

    var str = [_:0]u8{0} ** 128;
    var result: common.word_t = undefined;

    // TokenType.NoType
    copyWithZeroEnd(u8, &str, "  \t  123 \t ");
    result = try expr.expr(&str);
    try expect(result == 123);

    // TokenType.Equal
    copyWithZeroEnd(u8, &str, "123 == 123");
    result = try expr.expr(&str);
    try expect(result == 1);
    copyWithZeroEnd(u8, &str, "123 == 321");
    result = try expr.expr(&str);
    try expect(result == 0);

    // TokenType.NotEqual
    copyWithZeroEnd(u8, &str, "123 != 123");
    result = try expr.expr(&str);
    try expect(result == 0);
    copyWithZeroEnd(u8, &str, "123 != 321");
    result = try expr.expr(&str);
    try expect(result == 1);

    // TokenType.And
    copyWithZeroEnd(u8, &str, "1 && 2");
    result = try expr.expr(&str);
    try expect(result == 1);
    copyWithZeroEnd(u8, &str, "0 && 2");
    result = try expr.expr(&str);
    try expect(result == 0);
    copyWithZeroEnd(u8, &str, "0 && 0");
    result = try expr.expr(&str);
    try expect(result == 0);

    // TokenType.Or
    copyWithZeroEnd(u8, &str, "1 || 2");
    result = try expr.expr(&str);
    try expect(result == 1);
    copyWithZeroEnd(u8, &str, "0 || -2");
    result = try expr.expr(&str);
    try expect(result == 1);
    copyWithZeroEnd(u8, &str, "0 || 0");
    result = try expr.expr(&str);
    try expect(result == 0);

    // TokenType.Hex
    copyWithZeroEnd(u8, &str, "0x80000000");
    result = try expr.expr(&str);
    try expect(result == 0x80000000);

    // TokenType.Dec
    copyWithZeroEnd(u8, &str, "12345678");
    result = try expr.expr(&str);
    try expect(result == 12345678);

    // TokenType.Plus
    copyWithZeroEnd(u8, &str, "123 + 123");
    result = try expr.expr(&str);
    try expect(result == 246);
    // FIXME: What to do if integer overflow
    // copyWithZeroEnd(u8, &str, "0xffffffff + 1");
    // result = try expr.expr(&str);
    // FIXME: What to do if val is negative
    // copyWithZeroEnd(u8, &str, "123 + -122");
    // result = try expr.expr(&str);

    // TokenType.Minus
    copyWithZeroEnd(u8, &str, "222 - 111");
    result = try expr.expr(&str);
    try expect(@as(i32, @bitCast(result)) == 111);
    copyWithZeroEnd(u8, &str, "666 - 777");
    result = try expr.expr(&str);
    try expect(@as(i32, @bitCast(result)) == -111);

    // TokenType.Mul
    copyWithZeroEnd(u8, &str, "0 * 0x12345678");
    result = try expr.expr(&str);
    try expect(@as(i32, @bitCast(result)) == 0);
    copyWithZeroEnd(u8, &str, "123 * 456");
    result = try expr.expr(&str);
    try expect(@as(i32, @bitCast(result)) == 56088);

    // TokenType.Div
    copyWithZeroEnd(u8, &str, "0 / 123");
    result = try expr.expr(&str);
    try expect(@as(i32, @bitCast(result)) == 0);
    copyWithZeroEnd(u8, &str, "246 / 123");
    result = try expr.expr(&str);
    try expect(@as(i32, @bitCast(result)) == 2);
    // ExprError.DivZero
    copyWithZeroEnd(u8, &str, "123 / 0");
    _ = expr.expr(&str) catch |err| {
        try expect(err == expr.ExprError.DivZero);
    };

    // TokenType.LeftParen
    // TokenType.RightParen
    copyWithZeroEnd(u8, &str, "(123)");
    result = try expr.expr(&str);
    try expect(@as(i32, @bitCast(result)) == 123);

    // TokenType.Reg
    copyWithZeroEnd(u8, &str, "$pc");
    result = try expr.expr(&str);
    try expect(result == 0x80000000);

    // TokenType.Ref
    copyWithZeroEnd(u8, &str, "*$pc");
    result = try expr.expr(&str);
    try expect(result == 0x00000297);
    copyWithZeroEnd(u8, &str, "*0x80000010");
    result = try expr.expr(&str);
    try expect(result == 0xdeadbeef);

    // TokenType.Neg
    copyWithZeroEnd(u8, &str, "-1");
    result = try expr.expr(&str);
    try expect(@as(i32, @bitCast(result)) == -1);
    copyWithZeroEnd(u8, &str, "--123");
    result = try expr.expr(&str);
    try expect(@as(i32, @bitCast(result)) == 123);

    // ExprError.NoInput
    copyForwards(u8, &str, &([1]u8{0} ** 128));
    _ = expr.expr(&str) catch |err| {
        try expect(err == expr.ExprError.NoInput);
    };
    copyWithZeroEnd(u8, &str, " \t \t\t   ");
    _ = expr.expr(&str) catch |err| {
        try expect(err == expr.ExprError.NoInput);
    };

    // ExprError.TokenNoMatch
    copyWithZeroEnd(u8, &str, "@#$");
    _ = expr.expr(&str) catch |err| {
        try expect(err == expr.ExprError.TokenNoMatch);
    };

    // ExprError.BadExpr
    copyWithZeroEnd(u8, &str, "*");
    _ = expr.expr(&str) catch |err| {
        try expect(err == expr.ExprError.BadExpr);
    };

    // ExprError.PrinOpNotFound
    copyWithZeroEnd(u8, &str, "12 (34)");
    _ = expr.expr(&str) catch |err| {
        try expect(err == expr.ExprError.PrinOpNotFound);
    };

    // ExprError.ParenNotPair
    copyWithZeroEnd(u8, &str, "12 + ((34)");
    _ = expr.expr(&str) catch |err| {
        try expect(err == expr.ExprError.PrinOpNotFound);
    };
}
