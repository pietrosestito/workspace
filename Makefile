ROM    := build/boxhero.nes
LEVELS := $(sort $(wildcard levels/level*.txt))

.PHONY: all test clean

all: $(ROM)

build:
	mkdir -p build

build/chr.bin: tools/mkchr.py | build
	python3 tools/mkchr.py $@

build/levels.inc: tools/mklevels.py $(LEVELS) | build
	python3 tools/mklevels.py levels $@

build/main.o: src/main.s build/chr.bin build/levels.inc
	ca65 -g -I build --bin-include-dir build -o $@ src/main.s

$(ROM): build/main.o src/nes.cfg
	ld65 -C src/nes.cfg -Ln build/boxhero.lbl -o $@ build/main.o

test: $(ROM)
	python3 tools/smoketest.py $(ROM)

clean:
	rm -rf build
