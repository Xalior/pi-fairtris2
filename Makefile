#
# fairtris2 — Fairtris 2: The Ultimate Challenge as a bootable bare-metal
# Raspberry Pi image.
#
#   gmake check-toolchain    report the cross compiler this build will use
#   gmake check-deps         report the Circle world, the SDL2 archive and the
#                            Free Pascal compiler this build will use
#   gmake rpi5 | rpi4 | rpi3 one board's kernel image
#   gmake kernels            every board in BOARDS, built in parallel
#   gmake verify             truth-gate: every image exists and is non-empty
#   gmake card               stage the game's data into build/sd-card/
#   gmake clean-boards       drop every board's build tree
#
# Nothing here builds a Circle world or a Free Pascal compiler. Both are large,
# both belong to the repositories that own them, and a build that appears to
# want one started is a wrong variable — see check-deps.
#
# NOTHING HERE IS THE HOST KERNEL EITHER. The board bring-up, the card mount,
# the core split and the call into the Pascal program's entry point are
# circle-libfpc's host/host-kernel.mk, included below the same way fpc-app.mk
# and sdl-app.mk already are. This directory carries no C++ and no linker
# script: the game as a submodule, this Makefile, the patches its build
# applies to a copy of that submodule, and the script that stages the copy.
#
# The bench holds a Pi 5, and rpi5 is the only world built, so BOARDS names it
# alone. Set BOARDS to build more.
#

include mk/toolchain.mk

# Stated explicitly, because the first rule this file sees comes from an
# included makefile and that would otherwise decide the default goal.
.DEFAULT_GOAL := help

BOARDS ?= rpi5
BOARD  ?= rpi5

ifeq ($(filter $(BOARD),$(BOARDS) rpi3 rpi4 rpi5),)
$(error BOARD must be one of: rpi3 rpi4 rpi5 — not `$(BOARD)')
endif

IMAGE_rpi3 = kernel8
IMAGE_rpi4 = kernel8-rpi4
IMAGE_rpi5 = kernel_2712
IMAGE      = $(IMAGE_$(BOARD))

PORT = $(CURDIR)

# The dependencies this port consumes. Each default names this port's own
# pinned copy, so a checkout of this port is self-describing; a build inside a
# larger repository overrides them to point at that repository's editing copy,
# which is where the worlds and the compiler are actually built. Never build a
# world from here — a missing one is a wrong variable.
SHIM          ?= $(PORT)/circle-libsdl2
CIRCLE_WORLDS ?= $(PORT)/circle-libsdl2

# CIRCLE-LIBFPC IS THE ONE DEPENDENCY THIS PORT HAS NO COPY OF, and the default
# reaches out of the port to find it. It is the Free Pascal side of the build —
# the cross-compiler, its runtime and Free Pascal's packages, all of them built
# rather than checked out, and all of them shared with everything else in the
# parent repository. THE HOST KERNEL IS THIS DEPENDENCY'S TOO: circle-libfpc is
# the layer between Free Pascal's runtime and Circle, so the C++ that brings a
# board up and calls into a Pascal program's entry point lives there, at
# host/host-kernel.mk, and this port includes it rather than carrying a copy of
# its own. This port is a directory in that repository rather than a
# repository of its own, so naming its copy is honest; a port with a
# repository of its own would carry a pinned circle-libfpc the way it carries
# a pinned circle-libsdl2.
METAREPO      ?= $(PORT)/..
LIBFPC_HOME   ?= $(METAREPO)/circle-libfpc

FPC_COMPILER ?= $(LIBFPC_HOME)/fpc/compiler/ppcrossa64
FPC_UNITS    ?= $(LIBFPC_HOME)/fpc/rtl/units/aarch64-circlesdl2
# THE GAME NEEDS THE PACKAGE UNITS, not only the runtime ones: DateUtils and
# StrUtils for its clock and its text, IniFiles for its settings and its score
# tables, fgl for its containers. Every one of those lives in a package.
FPC_PACKAGES ?= $(LIBFPC_HOME)/fpc/packages

# WHERE THE GAME'S FILES ARE ON THE CARD, AND IT IS A BUILD PARAMETER.
#
# The kernel gives two answers about the card and both come from this: the
# working directory, which is what makes the game's own relative paths resolve;
# and the base path SDL_GetPrefPath is derived from, which is where the game
# writes its settings and its high scores. The kernel's own default is the
# card's root; this port sets its own, following the convention every game in
# this family uses — one directory per game under /games.
RAPI_WORK_DIR ?= /games/fairtris2

# THE VIRTUAL DISPLAY SIZE, AND IT IS A BUILD PARAMETER TOO.
#
# The game's own SDL_CreateWindow call asks for 0x0 and resizes itself
# afterwards with SDL_SetWindowSize, which this shim does not implement --
# see circle-libfpc's host/kernel.cpp header comment. Nothing in the kernel or
# the library names a size for it, so this is the only place anywhere that
# does: it is stamped into the built image's own boot argument block
# (bootargs.cpp) by circle-libsdl2's tools/stamp-bootargs, below, so the image
# carries it with nothing passed at boot time. Fairtris draws a 336x240 buffer
# of NES pixels, 8:7 rather than square (BUFFER_WIDTH/BUFFER_HEIGHT and
# BUFFER_PIXEL_RATIO_X), so 384x240 is that picture in square pixels and the
# library performs the only scale, fitting the VFB to the panel.
RAPI_VDISPLAY ?= 384x240

# Passed to every self-recursive board build below. Each has a default above
# naming this port's own pinned copy; the parent repository overrides them to
# its editing copies, where the worlds and the compiler are actually built.
BOARD_ARGS = SHIM=$(SHIM) CIRCLE_WORLDS=$(CIRCLE_WORLDS) \
	LIBFPC_HOME=$(LIBFPC_HOME) FPC_COMPILER=$(FPC_COMPILER) \
	FPC_UNITS=$(FPC_UNITS) FPC_PACKAGES=$(FPC_PACKAGES) \
	RAPI_WORK_DIR=$(RAPI_WORK_DIR) RAPI_VDISPLAY=$(RAPI_VDISPLAY)

.PHONY: help kernels rebuild verify card clean-boards check-deps $(BOARDS)
.PHONY: $(addprefix rebuild-,$(BOARDS)) build check-deps-report clean-board

help:
	@sed -n '2,26p' $(firstword $(MAKEFILE_LIST)) | sed 's/^# \{0,1\}//'

# ---------------------------------------------------------------------------
# Every board at once, one board, or a rebuild. Each self-recurses into this
# same Makefile with BOARD set and an explicit target, because the board's
# world, its object directory and its image name are all settled once per
# parse from BOARD — a single parse cannot answer for two boards, any more
# than host/Makefile could when this was two files.
# ---------------------------------------------------------------------------

# What this build will reach for, reported rather than assumed. Answered by a
# recursive parse for the first board in BOARDS, because that is where WORLD,
# GAME_CHECKOUT and the rest are settled.
check-deps:
	+@$(NOT_DRY_RUN)
	@$(MAKE) --no-print-directory BOARD=$(firstword $(BOARDS)) $(BOARD_ARGS) check-deps-report

$(BOARDS): check-toolchain
	+@$(NOT_DRY_RUN)
	$(MAKE) BOARD=$@ $(BOARD_ARGS) build

# Every board at once. Each owns a different world and a different output
# directory, so there is nothing for them to collide on.
#
# Each board is waited for BY PID, and its status kept. A bare `wait` reports
# only that the shell has no children left — it is success whatever the jobs
# did — so a board that failed to build would leave this target reporting
# success, and the truth-gate would then pass that board's PREVIOUS image,
# still on disk.
kernels: check-toolchain
	+@$(NOT_DRY_RUN)
	@pids=; fail=0; \
	for b in $(BOARDS); do $(MAKE) BOARD=$$b $(BOARD_ARGS) build & pids="$$pids $$!"; done; \
	for p in $$pids; do wait $$p || fail=1; done; \
	exit $$fail

# One board from nothing: its build tree is removed first, so no object and no
# staged source can be inherited from a previous build. A static pattern rule
# over the board list, because make does not apply pattern rules to phony
# targets and would answer "nothing to be done".
$(addprefix rebuild-,$(BOARDS)): rebuild-%: check-toolchain
	+@$(NOT_DRY_RUN)
	$(MAKE) BOARD=$* $(BOARD_ARGS) clean-board
	$(MAKE) BOARD=$* $(BOARD_ARGS) build

rebuild: check-toolchain
	+@$(NOT_DRY_RUN)
	@pids=; fail=0; \
	for b in $(BOARDS); do \
		( $(MAKE) BOARD=$$b $(BOARD_ARGS) clean-board && \
		  $(MAKE) BOARD=$$b $(BOARD_ARGS) build ) & pids="$$pids $$!"; \
	done; \
	for p in $$pids; do wait $$p || fail=1; done; \
	exit $$fail

# Truth-gate: ask the filesystem, not the exit codes. An image that is missing
# or empty fails here even if the build claimed success.
#
# What this cannot tell you is whether the image was built from the sources as
# they now stand. That is a question about the build, not about the file, and
# `gmake rebuild` is the only answer to it.
verify:
	@fail=0; \
	for b in $(BOARDS); do \
		case $$b in \
			rpi3) img=build/rpi3/$(IMAGE_rpi3).img ;; \
			rpi4) img=build/rpi4/$(IMAGE_rpi4).img ;; \
			rpi5) img=build/rpi5/$(IMAGE_rpi5).img ;; \
		esac; \
		if [ ! -s "$$img" ]; then \
			echo "  FAIL  $$img missing or empty"; fail=1; \
		else \
			echo "  OK    $$img ($$(wc -c < $$img | tr -d ' ') bytes)"; \
		fi; \
	done; \
	exit $$fail

# ---------------------------------------------------------------------------
# The game's data
# ---------------------------------------------------------------------------
#
# Fairtris 2 ships its own graphics, sounds and backgrounds, and its author
# released the whole project into the public domain (see fairtris2/LICENSE), so
# unlike most games in this family there is nothing to download and no licence
# gate. The data is in the pinned checkout and is copied straight out of it.
#
# WHAT IS LEFT OUT: the three Windows DLLs beside it. SDL2 on this machine is
# circle-libsdl2, linked into the image; a loader that could open a DLL does
# not exist here.
#
# WHAT IS ADDED: the two empty score directories. The game writes its high
# scores through SDL_GetPrefPath, which is <game dir>/furious-programming/
# fairtris2/, and it writes a file into scores/ntsc and scores/pal rather than
# creating them.
#
# This stages a directory to copy onto a card formatted elsewhere. It writes no
# firmware, no boot configuration and no kernel image: this port has never been
# booted on hardware, so nothing here claims to be a whole card.
CARD_DIR = build/sd-card

card:
	@rm -rf $(CARD_DIR)
	@dest=$(CARD_DIR)$(RAPI_WORK_DIR); \
	mkdir -p "$$dest"; \
	if [ ! -d fairtris2/bin ]; then \
		echo "  CARD  no game data at fairtris2/bin — the submodule is not"; \
		echo "        checked out: git submodule update --init fairtris2"; \
		exit 1; \
	fi; \
	for d in grounds sprites sounds licenses; do \
		[ -d "fairtris2/bin/$$d" ] || { echo "  CARD  fairtris2/bin/$$d is missing"; exit 1; }; \
		cp -R "fairtris2/bin/$$d" "$$dest/"; \
	done; \
	mkdir -p "$$dest/furious-programming/fairtris2/scores/ntsc" \
		 "$$dest/furious-programming/fairtris2/scores/pal"; \
	echo "  CARD  staged $(CARD_DIR) — copy its contents to the root of the card"; \
	echo "        the game will look for its files at $(RAPI_WORK_DIR)"

clean-boards:
	@for b in $(BOARDS); do $(MAKE) BOARD=$$b $(BOARD_ARGS) clean-board; done
	@rm -rf $(CARD_DIR)

# ---------------------------------------------------------------------------
# One board's build. Guarded on its world being configured, so `help`,
# `verify`, `card` and `clean-boards` above answer with no world at all — a
# missing one is reported by check-deps and refused here, never assumed.
# ---------------------------------------------------------------------------

WORLD = $(CIRCLE_WORLDS)/circle-stdlib-$(BOARD)

ifneq ($(wildcard $(WORLD)/Config.mk),)

include $(WORLD)/Config.mk

OBJDIR = build/$(BOARD)
TARGET = $(OBJDIR)/$(IMAGE)

# ---------------------------------------------------------------------------
# The game's source, copied and patched
# ---------------------------------------------------------------------------
#
# THIS RUNS WHILE MAKE READS THIS FILE, not from a recipe, and it has to.
# fpc-app.mk reads the unit source directories as it is parsed — to check they
# exist, and to make every Pascal file a prerequisite of the program's object —
# so the staged tree must be there before make decides anything.
#
# tools/stage-game does the work and explains itself; what matters here is that
# it refuses rather than improvises. A checkout that is not there, a checkout
# somebody has edited, a patch that does not apply: each stops the build with a
# message naming what to do, and a patch that fails takes the staged tree with
# it so no image can be built from a half-patched one.
#
# Its progress goes to stderr and reaches the terminal directly. The one word
# on stdout is what is tested here.
GAME_CHECKOUT = $(PORT)/fairtris2
PATCH_DIR     = $(PORT)/patches
GAME_STAGE    = $(CURDIR)/$(OBJDIR)/game
GAME_SRC      = $(GAME_STAGE)/source

GAME_STAGED := $(shell $(PORT)/tools/stage-game \
	'$(GAME_CHECKOUT)' '$(GAME_STAGE)' '$(PATCH_DIR)')
ifneq ($(GAME_STAGED),ok)
$(error the game source could not be staged — see the STAGE lines above)
endif

# ---------------------------------------------------------------------------
# The host kernel
# ---------------------------------------------------------------------------
#
# Circle-libfpc's, not this port's — see host/host-kernel.mk there for what it
# does and why. Before Rules.mk, it needs the C++ dialect and the dependency-
# tracking switch it and this port's own compile both use.
STANDARD   = -std=c++23 -Wno-volatile
CHECK_DEPS = 0

# sdl-app.mk replaces Circle's own $(TARGET).img rule. Pointing TARGET at a
# name nothing builds while Rules.mk is read attaches its rule there instead.
SDL_APP_IMAGE := $(TARGET)
TARGET := $(OBJDIR)/.circle-unused
include $(CIRCLEHOME)/Rules.mk
TARGET := $(SDL_APP_IMAGE)

include $(LIBFPC_HOME)/host/host-kernel.mk
OBJS = $(HOST_KERNEL_OBJS)

# ---------------------------------------------------------------------------
# The game
# ---------------------------------------------------------------------------
#
# WHERE THE PASCAL SOURCE IS, AND IN WHICH ORDER IT IS SEARCHED.
#
#   $(GAME_SRC)      the game's units, in the patched copy staged above.
#   $(GAME_SRC)/sdl  the SDL2-for-Pascal binding the game vendored, patched in
#                    the same copy. The library it names is resolved at link
#                    time against circle-libsdl2 instead of against a DLL.
#   units/           circle-libsdl2's Circle extensions, which no SDL binding
#                    carries because they are not in SDL's headers. The GAME
#                    never names this unit — the host kernel makes every Circle
#                    declaration — but it is on the path for anything that does.
FPC_UNIT_SRC_DIRS = $(GAME_SRC) $(GAME_SRC)/sdl $(LIBFPC_HOME)/units

# fpc-app.mk needs PREFIX and AR, which Rules.mk has just settled, and its
# results have to be in hand before LIBS and OBJS are finished below.
FPC_APP      = $(GAME_SRC)/Fairtris.Main.lpr
FPC_BLOB_DIR = $(OBJDIR)/fpcblob
include $(LIBFPC_HOME)/fpc-app.mk

ifeq ($(strip $(FPC_PACKAGE_UNITS)),)
$(error no package units under $(FPC_PACKAGES). Build them with `gmake fpc-packages' in the parent repository; this game is written in units that live there)
endif

# The game's own object joins the kernel's. sdl-app-init.ld defers the
# constructors of everything arriving as an OBJECT until the kernel exists, and
# runs everything arriving as an ARCHIVE member early; the game is the
# application, so it belongs on the object side of that line.
OBJS += $(FPC_APP_OBJS)

# The Free Pascal runtime units and this library's C half go inside the link's
# --start-group with everything else: the game's object and the runtime refer
# to each other in both directions, so neither can simply come first.
LIBS := $(FPC_APP_LIBS) $(SHIM)/libSDL2-$(BOARD).a $(CIRCLE_STDLIB_LIBS)

include $(SHIM)/sdl-app.mk

# THE STAMP RUNS ON EVERY INVOCATION, not only when the image is relinked:
# `build` is phony, so a change to RAPI_VDISPLAY alone (no source touched)
# still reaches the image. circle-libsdl2's tools/stamp-bootargs rewrites the
# block's Text field whole, so stamping an already-stamped image is not
# cumulative. It is SHIM's tool, not this port's -- SHIM is how this
# Makefile already locates circle-libsdl2, whether that is this port's own
# pinned copy or a larger repository's editing copy (see SHIM, above).
build: $(TARGET).img
	@$(SHIM)/tools/stamp-bootargs $(TARGET).img "--rapi-vdisplay=$(RAPI_VDISPLAY)"

# What this build reached for, read out of the variables that decided it. Every
# line is a path; the mark beside it says whether that path is there. Nothing
# here builds anything, and a missing world or compiler is reported rather than
# started.
check-deps-report:
	@echo "  BOARD     $(BOARD)"
	@echo "  WORK DIR  $(RAPI_WORK_DIR)"
	@for p in "GAME      $(GAME_CHECKOUT)/source" \
		  "WORLD     $(WORLD)/Config.mk" \
		  "ARCHIVE   $(SHIM)/libSDL2-$(BOARD).a" \
		  "LIBFPC    $(LIBFPC_HOME)/fpc-app.mk" \
		  "COMPILER  $(FPC_COMPILER)" \
		  "RTL       $(FPC_UNITS)" \
		  "PACKAGES  $(FPC_PACKAGES)"; do \
		path=$${p#* }; path=$${path##* }; \
		if [ -e "$$path" ]; then echo "  $$p"; else echo "  $$p   ABSENT"; fi; \
	done

clean-board: fpc-app-clean
	@rm -rf $(OBJDIR)

else

build check-deps-report clean-board:
	@echo "the $(BOARD) world is not configured ($(WORLD)/Config.mk is missing)."
	@echo "CIRCLE_WORLDS says where the worlds are; they are circle-libsdl2's to"
	@echo "build, never this build's to start."
	@exit 1

endif

# Without this the pattern rule above matches this file and make rebuilds its
# own makefile before doing anything asked for.
Makefile: ;
