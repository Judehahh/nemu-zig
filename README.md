# nemu-zig

My nemu (NJU EMUlator) implement in Zig.

---

`nemu-zig` is developed with the master branch version of Zig. The latest tested zig version is `0.12.0-dev.2668+ddcea2cad`.

## How To Run

First make sure `zig` is in your `$PATH`. (The pre-built binary of Zig can be downloaded from [here](https://ziglang.org/download/))

### Build And Run NEMU
```
zig build run
```

### Run Unit Tests

Zig provides `zig test` which can be used to ensure behavior meets expectations. 

Unit tests are defined in `src/test.zig`. But now only `expr test` was supported.

```
zig build test
```