test:
	zig build test

difftest:
	zig build -DDIFFTEST=true -DITRACE=true run -- -l zig-out/nemu-log.txt -d lib/riscv32-spike-so -p 1234 $(IMG)

run:
	echo "c" | zig build -DISA=$(ISA) run -- $(ARGS) $(IMG)
