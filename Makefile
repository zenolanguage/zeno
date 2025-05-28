CC = cc
LUAJIT = ./fennel/luajit/src/luajit
FENNEL = ./fennel/fennel

run: $(FENNEL)
	$(FENNEL) zeno.fnl $(ARGS)

./fennel:
	git clone --depth=1 --recurse-submodules=luajit https://git.sr.ht/~technomancy/fennel

./fennel/luajit/src/luajit: ./fennel
	MACOSX_DEPLOYMENT_TARGET=15.6 make -C ./fennel/luajit CC=$(CC) -j4

./fennel/fennel: ./fennel ./fennel/luajit/src/luajit
	make -C ./fennel LUA="$$PWD/fennel/luajit/src/luajit"

clean:
	rm -rf ./fennel

.PHONY: run clean
