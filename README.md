# nemu-zig

My nemu (NJU EMUlator) implement in Zig. Now supports `riscv32im` ISA.

---

`nemu-zig` is developed with the master branch version of Zig. The latest tested zig version is `0.12.0-dev.2823+955fd65cb`.

## How To Run

First make sure `zig` is in your `$PATH`. (The pre-built binary of Zig can be downloaded from [here](https://ziglang.org/download/))

### Build And Run NEMU

Run built-in image:

```
zig build run
```

Run your own image:

```
zig build run -- /path/to/image.bin
```

Run with disasm:

> `llvm` needs to be installed before running disasm.

```
zig build -DITRACE run
```

Run with difftest:

nemu support comparing running result with `spike` while simulating riscv32.

```shell
make difftest IMG=/path/to/image.bin
```

### Run Unit Tests

Zig provides `zig test` which can be used to ensure behavior meets expectations. 

Unit tests are defined in `src/test.zig`. But now only `expr test` was supported.

```
zig build test
```

## Possible problems

### library 'LLVM' not found

This problem may occur when running nemu-zig with disasm on Debian-based systems.

```shell
-> % zig build -DITRACE                                                         
install                                                          
└─ install nemu-zig                                              
   └─ zig build-exe nemu-zig Debug native failure                                                                                 
error: error: unable to find Dynamic system library 'LLVM' using strategy 'paths_first'. searched paths:
```

Solution:

```zig
// build.zig

// change this line
exe.linkSystemLibrary("LLVM");
// to (modified "16" to your llvm version)
exe.linkSystemLibrary("LLVM-16");
```

### 'llvm-c/*.h' file not found

This problem may occur when running nemu-zig with disasm on Debian-based systems.

```shell
nemu/lib/llvm_slim.h:1:10: error: 'llvm-c/Disassembler.h' file not found
#include <llvm-c/Disassembler.h>
         ^~~~~~~~~~~~~~~~~~~~~~~~
```

Solution:

```shell
# Modified "16" to your llvm version
sudo ln -s /usr/include/llvm-c-16/llvm-c/ /usr/include/llvm-c
sudo ln -s /usr/include/llvm-16/llvm /usr/include/llvm
```
