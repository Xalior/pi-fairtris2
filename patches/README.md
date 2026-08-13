# patches/

Everything Fairtris 2 needs changed to compile for this target. There are four
edits in total, in six files, and all of them are compile-time guards.

## They are never applied to the checkout

`../fairtris2` is a submodule pinned at an upstream commit, and this port does
not fork the games it builds. The build copies the game's `source/` tree into
`host/build/<board>/game/` and applies these patches to the copy. `tools/stage-game`
does that, and `host/Makefile` calls it while make is still reading the
makefile, because the Free Pascal build reads the source directory to work out
what the program depends on.

What the copy buys:

- The checkout is never dirty, so `git status` reporting it modified is a real
  alarm rather than the normal state of a build tree. The staging tool stops
  when it sees one.
- A patch applies to a known-good tree or it does not apply at all. There is no
  "already applied" state to reason about and no half-patched tree to inherit.
- Advancing the pin to a newer upstream either still works or fails at the
  point a person can read why. A failed patch removes the staged tree and stops
  the build, naming the patch that failed and printing what `patch` said about
  it. No image is ever built from a partly patched tree.

To apply them by hand — to a copy, never to the checkout:

```sh
patch -p1 -d <copy-of-the-game> < patches/01-non-windows-guards.patch
```

They are numbered because they are applied in name order, and they carry the
game-relative paths upstream uses (`a/source/...`), so a diff reads correctly
against the upstream repository.

Each patch file begins with a prose header saying what it changes and why.
`patch` skips leading text, so the header travels with the patch rather than
in a separate note that can be lost.

## `01-non-windows-guards.patch`

The three places the game assumes it is on Windows: an x86 `pause` instruction
in the frame limiter's spin loop, the help screen opening a web browser through
the Lazarus component library, and a Windows resource file linked into the
program for its icon. Each gets a guard; each keeps its existing behaviour on
the platform that already had it.

## `02-sdl2-for-pascal-circlesdl2.patch`

The fourth platform arm for SDL2-for-Pascal, the binding the game vendors in
`source/sdl/`. The binding declares its library-name constants in three arms —
Windows, Unix, Classic Mac OS — and a target matching none of them fails to
compile with `identifier not found`, naming neither the constant's purpose nor
the platform.

This is the same change `circle-libfpc/patches/sdl2-for-pascal-circlesdl2.patch`
makes, against the copy of the binding that library vendors. It is cut again
here because the game carries its own copy of the binding and this build
compiles that one — the game's source tree is what gets staged, so the binding
inside it is what gets patched. circle-libfpc's own `patches/README.md` records
which other platform arms were tried instead and how each one failed; that
record is not repeated here.
