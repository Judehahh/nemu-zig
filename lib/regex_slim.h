//! Workaround for using regex in Zig.
//! https://zigcc.github.io/zig-cookbook/15-01-regex.html

#include <regex.h>
#include <stdlib.h>

regex_t* alloc_regex_t(void);
void free_regex_t(regex_t* ptr);