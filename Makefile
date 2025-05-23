ifeq ($(OS),Windows_NT)
	ARGS = ""
	OUT = zeno.exe
else
	ARGS = "-lc"
	OUT = zeno
endif

$(OUT): zeno.rs
	rustc --edition 2021 -C opt-level=z -C link-args=$(ARGS) -C panic="abort" -o $(OUT) $<

run: $(OUT)
	./$<

clean:
	rm -f zeno zeno.exe zeno.pdb

.PHONY: run clean
