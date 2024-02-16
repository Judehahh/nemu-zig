# nemu-zig

My nemu (NJU EMUlator) implement in Zig.

---

`nemu-zig` is developed with the master branch version of Zig. The latest tested zig version is `0.12.0-dev.2763+7204eccf5`.

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

### Run Unit Tests

Zig provides `zig test` which can be used to ensure behavior meets expectations. 

Unit tests are defined in `src/test.zig`. But now only `expr test` was supported.

```
zig build test
```