# fairtris2

**Fairtris 2: The Ultimate Challenge running directly on a Raspberry Pi with
no operating system.** The board powers on and the game is what boots: no
Linux, no desktop, no launcher, and nothing else running beside it.

## What this is

[Fairtris 2](https://github.com/g-maxim-u/Fairtris-2-UC) is an ordinary SDL2
game, written in Free Pascal for Windows. This directory holds what is
specific to this port — the game, patched, and the two values below — and
nothing else: no [Circle](https://github.com/rsta2/circle) kernel, no SDL2,
no C or C++ of any kind. Starting the board, mounting the card, and calling
into the game's entry point is circle-libfpc's, the Free Pascal side of the
same idea, and [circle-libsdl2](https://github.com/Xalior/circle-libsdl2) is
the SDL2 that kernel is built on. This port includes both rather than
carrying a copy of either.

It is the first Free Pascal game in this family. Every other port is C or C++.

The game's own source is not copied into this repository and not modified in
it. It is a submodule, pinned at an upstream commit. The build reads it, copies
what it needs, and never writes to it.

## What state this is in

**The image has never been started on real hardware.** It builds, and that is
all this directory currently claims. Nothing here has been seen to draw a
picture, read the card, or respond to a control.

Only the Raspberry Pi 5 is built. The Pi 3 and Pi 4 need a Circle world of
their own, and those are not built in the parent repository.

## Layout

```
fairtris2/          the game, a submodule, pinned at upstream and never written to
circle-libfpc/      the Free Pascal side of the build, a submodule, pinned
rapi-bootloader/    the board bring-up this family boots through, a submodule, pinned
patches/            the four compile-time guards the game needs, as patch files
tools/stage-game    copies the game's source into the build tree and patches the copy
mk/toolchain.mk     finds the cross compiler
Makefile            the build
```

`circle-libsdl2` is not a direct dependency of this repository. It is
`circle-libfpc`'s own dependency, and belongs one level deeper — a submodule
of `circle-libfpc`, arriving through this repository's recursive clone rather
than a submodule of its own here. See "Where this lives" below for how that
dependency is wired.

There is no C or C++ here, and nothing written for this port starts the board.
That is circle-libfpc's host kernel (`host/kernel.cpp` there), included the
way `fpc-app.mk` and `sdl-app.mk` already are. It makes three declarations on
the game's behalf that a desktop would have worked out for itself: the size of
the display, where the game's files are, and what the working directory is —
the first is `RAPI_VDISPLAY` below, the other two follow from `RAPI_WORK_DIR`.
circle-libfpc's own `host/kernel.h` explains each one.

## Building

The build needs the Arm GNU `aarch64-none-elf` cross toolchain, a built Circle
world for the board, and a built Free Pascal cross-compiler. It builds none of
them. If a build appears to want one of them started, a variable is wrong.

```sh
gmake check-toolchain     # which cross compiler this will use
gmake check-deps          # every path this build will reach for, and whether it is there
gmake rpi5                # the image
gmake verify              # the image exists and is not empty
gmake card                # stage the game's data files
```

The image is `build/rpi5/kernel_2712.img`.

Inside a larger repository that vendors this port, it is built through that
repository's own makefile, which knows where its editing copies of the
dependencies are:

```sh
gmake fairtris2           # the image
gmake fairtris2-card      # the data files
```

## The card

`gmake card` stages a directory into `build/sd-card/`. Copy its contents to the
root of a card the board can boot.

It writes the game's data files and nothing else — no firmware, no boot
configuration, and no kernel image. This port has never been booted, so nothing
here claims to produce a whole card.

The game's files go in one directory, `/games/fairtris2`, which is the
convention every game in this family follows: one directory per game, and the
root of the card stays clear. That path is a build parameter, not a fixed
value — the kernel's own default is the card's root, and this port sets its
own. A card laid out differently is a `RAPI_WORK_DIR` setting, not an edit to
the kernel:

```sh
gmake rpi5 card RAPI_WORK_DIR=/somewhere/else
```

The kernel gives two answers derived from it — the working directory, which is
what makes the game's own relative paths work, and the base path SDL derives
the preferences path from, which is where the game writes its settings and its
high scores. Both come from the one value, so the two can never disagree.

## The patches, and why there are patch files at all

Fairtris 2 does not compile for this target unchanged. Four things need a
compile-time guard: an x86 `pause` instruction in the frame limiter, a call
that opens a web browser, a Windows resource file, and the missing platform arm
in the SDL2 binding the game vendors. Every one is a guard. Nothing is removed
and nothing is rewritten.

**We do not fork the games we port.** So the build copies the game's `source/`
tree into `build/<board>/game/` and applies `patches/` to the copy. The
checkout stays exactly as upstream published it.

That copy is what makes the rest true. The submodule is never dirty, so
`git status` reporting it modified is a real alarm rather than the normal state
of a build tree — and the staging tool stops when it sees one. A patch applies
to a known-good tree with no fuzz allowed, or it does not apply at all: there is
no partly-patched tree to inherit and no "already applied" state to reason
about. A patch that fails takes the staged tree with it and stops the build,
naming the patch and printing what `patch` said, so advancing the pin to a newer
upstream either still works or fails where a person can read why.

`patches/README.md` describes each patch. Each patch file also carries its own
explanation in its header.

## Where this lives

This is its own repository. `fairtris2` (the game), `circle-libfpc` and
`rapi-bootloader` are each a real submodule, pinned at a published commit, so
a fresh clone with `--recurse-submodules` gets everything this repository
names directly.

`circle-libfpc` owns both of its own dependencies as submodules of its own:
`circle-libsdl2`, and the Free Pascal compiler, runtime and packages built for
the `circlesdl2` target. Both arrive through this repository's recursive
clone rather than living in this repository directly, and `circle-libfpc`'s
`Makefile` defaults `CIRCLE_WORLDS`, `SHIM`, `FPC_COMPILER`, `FPC_UNITS` and
`FPC_PACKAGES` to those nested submodules.

A repository that vendors this port as a submodule of its own — building
several boards' worth of ports side by side, say — can still override the
build's dependency variables (`CIRCLE_WORLDS`, `SHIM`, `LIBFPC_HOME`,
`FPC_COMPILER`, `FPC_UNITS`, `FPC_PACKAGES`) to point at its own editing
copies instead of this port's pinned ones. See the Makefile's own comments
above `SHIM` and `LIBFPC_HOME` for how that override works.

## Licences

Fairtris 2 is released into the public domain by its author — see
`fairtris2/LICENSE`. Its data files ship in the game's own repository, so unlike
most games in this family there is nothing to download and no licence gate on
the data.
