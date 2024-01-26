const config = @import("config");

pub const word_t = if (config.ISA64) u64 else u32;
pub const sword_t = if (config.ISA64) i64 else i32;

pub const vaddr_t = word_t;
pub const paddr_t = if (config.MBASE + config.MSIZE > 0x100000000) u64 else u32;
pub const ioaddr_t = u16;
