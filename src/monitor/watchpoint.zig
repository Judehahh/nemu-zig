const std = @import("std");
const expr = @import("expr.zig");
const common = @import("../common.zig");
const util = @import("../util.zig");
const state = @import("../state.zig");

const vaddr_t = common.vaddr_t;

pub const WpError = error{
    NoFreeWp,
    OutOfRange,
    WpNotFount,
    NoWp,
} || expr.ExprError;

pub fn WpErrorHandler(err: anyerror) void {
    switch (err) {
        WpError.NoFreeWp => std.debug.print("No free watchpoint.\n", .{}),
        WpError.OutOfRange, WpError.WpNotFount => std.debug.print("No such watchpoint.\n", .{}),
        WpError.NoWp => std.debug.print("No watchpoints.\n", .{}),
        else => {},
    }
}

const WatchPoint = struct {
    no: usize,
    next: ?*WatchPoint,
    expr: std.mem.TokenIterator(u8, .any),
    val: common.word_t,
};

const max_watchpoint = 32;
const max_buf_len = 1024;

var wp_pool: [max_watchpoint]WatchPoint = undefined;
var expr_buf = [_][max_buf_len]u8{
    [_]u8{0} ** max_buf_len,
} ** max_watchpoint;
var head: ?*WatchPoint = undefined;
var free_: ?*WatchPoint = undefined;

pub fn init_wp_pool() void {
    var i: usize = 0;
    while (i < max_watchpoint) : (i += 1) {
        wp_pool[i].no = i;
        wp_pool[i].next = if (i < max_watchpoint - 1) &wp_pool[i + 1] else null;
        wp_pool[i].expr = undefined;
    }

    head = null;
    free_ = &wp_pool[0];
}

/// Pick a wp from free_ and insert it into the front of head.
fn new_wp() !*WatchPoint {
    if (free_ == null)
        return WpError.NoFreeWp;

    const wp: *WatchPoint = free_.?; //cannot be null
    free_ = wp.next;
    return wp;
}

/// Give back the wp into free_.
fn free_wp(wp: *WatchPoint) void {
    wp.next = free_;
    free_ = wp;
}

/// Accept a TokenIterator parameter and create a watchpoint node by
/// copying tokens into private expr buffer, then return the node number.
pub fn add_wp(tokens: std.mem.TokenIterator(u8, .any)) !usize {
    const wp = try new_wp();
    wp.expr = std.mem.tokenize(u8, expr_buf[wp.no][0..tokens.buffer.len], " \t\r\n");
    @memcpy(expr_buf[wp.no][0..tokens.buffer.len], tokens.buffer);
    wp.expr.index = tokens.index;

    wp.val = expr.expr(&wp.expr) catch |err| {
        expr.ExprErrorHandler(err);
        free_wp(wp);
        return err;
    };
    wp.next = head;

    head = wp;
    return wp.no;
}

/// Delete a watchpoint from head list by wathpoint number, and clear its expr buffer.
pub fn del_wp(no: usize) !void {
    if (no >= max_watchpoint) return WpError.OutOfRange;

    var wp: ?*WatchPoint = head;
    var prev: ?*WatchPoint = null;
    while (wp != null) : (wp = wp.?.next) {
        if (wp.?.no == no) break;
        prev = wp;
    } else {
        return WpError.WpNotFount;
    }

    if (prev == null) {
        head = wp.?.next;
    } else {
        prev.?.next = wp.?.next;
    }

    @memset(&expr_buf[wp.?.no], 0);
    free_wp(wp.?);
}

pub fn check_wp(pc: common.vaddr_t) !void {
    var wp: ?*WatchPoint = head;

    while (wp != null) : (wp = wp.?.next) {
        var tokens = wp.?.expr;
        const val = try expr.expr(&tokens); // error will not occur here theoretically

        if (val != wp.?.val) {
            std.debug.print("hit watchpoint at pc = 0x{x:0>8}, expr = ", .{pc});
            util.print_tokens(wp.?.expr);
            std.debug.print("\nold value = " ++ common.fmt_word ++ ", new value = " ++ common.fmt_word ++ "\n", .{ wp.?.val, val });

            wp.?.val = val;

            // If nemu state has turned to END, chaing its state to STOP will cause it to run continue.
            if (state.nemu_state.state != state.NEMUState.NEMU_END)
                state.nemu_state.state = state.NEMUState.NEMU_STOP;
        }
    }
}

pub fn list_wp() !void {
    if (head == null) {
        return WpError.NoWp;
    }

    var wp: ?*WatchPoint = head;
    while (wp != null) : (wp = wp.?.next) {
        std.debug.print("No.{d}\t", .{wp.?.no});
        util.print_tokens(wp.?.expr);
        std.debug.print("\n", .{});
    }
}