#!/usr/bin/env sh
set -e

if [ "$1" = clean ]; then rm -rf .build; exit; fi # NOTE: hardcoding .build so users don't delete their root directories lol

CC=${CC:-cc}
OUTDIR=${OUTDIR:-.build}

mkdir -p $OUTDIR
[ -d $OUTDIR/fennel ] || git clone --depth=1 --recurse-submodules=luajit https://git.sr.ht/~technomancy/fennel $OUTDIR/fennel
[ -x $OUTDIR/fennel/luajit/src/luajit ] || make -j 4 -C $OUTDIR/fennel/luajit MACOSX_DEPLOYMENT_TARGET=15.6
[ -x $OUTDIR/fennel/fennel ] || make -C $OUTDIR/fennel LUA=$(readlink -f $OUTDIR)/fennel/luajit/src/luajit
$(readlink -f $OUTDIR)/fennel/fennel zeno.fnl
$CC -o $OUTDIR/zeno zeno.c

[ "$1" = run ] && $(readlink -f $OUTDIR)/zeno
