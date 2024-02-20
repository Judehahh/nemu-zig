const config = @import("config");

pub const word_t = if (config.ISA64) u64 else u32;
pub const sword_t = if (config.ISA64) i64 else i32;
pub const double_t = if (config.ISA64) u128 else u64;
pub const sdouble_t = if (config.ISA64) i128 else i64;
pub const fmt_word = if (config.ISA64) "0x{x:0>16}" else "0x{x:0>8}";

pub const vaddr_t = word_t;
pub const paddr_t = if (config.MBASE + config.MSIZE > 0x100000000) u64 else u32;
pub const ioaddr_t = u16;
