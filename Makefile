run:
	echo "c" | zig build -DISA=$(ISA) run -- $(ARGS) $(IMG)
