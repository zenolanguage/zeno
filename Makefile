CC ?= cc
CFLAGS ?= -std=c99 -Wall -Wextra -ggdb

all: zeno

zeno: zeno.c
	$(CC) $(CFLAGS) -o $@ $<

clean:
	rm -rf zeno zeno.o zeno.dSYM

.PHONY: all clean
