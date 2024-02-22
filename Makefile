ifeq ($(shell uname -m),x86_64)
    DIFF_REF_SO = prebuilt/riscv32-spike-ref-x86_64-linux.so
else ifeq ($(shell uname -m),aarch64)
    DIFF_REF_SO = prebuilt/riscv32-spike-ref-aarch64-linux.so
else
    $(error Unsupport host architecture for difftest!)
endif

test:
	zig build test

difftest:
	zig build -DDIFFTEST=true -DITRACE=true run -- -l zig-out/nemu-log.txt -d $(DIFF_REF_SO) -p 1234 $(IMG)

run:
	echo "c" | zig build -DISA=$(ISA) run -- $(ARGS) $(IMG)
