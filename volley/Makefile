ROM := build/volley.nes

.PHONY: all test clean

all: $(ROM)

build:
	mkdir -p build

build/assets.inc build/chr.bin build/title.nam build/game.nam &: tools/mkassets.py ../tools/mkchr.py | build
	python3 tools/mkassets.py build

build/main.o: src/main.s build/assets.inc
	ca65 -g -I build --bin-include-dir build -o $@ src/main.s

$(ROM): build/main.o src/nes.cfg
	ld65 -C src/nes.cfg -Ln build/volley.lbl -o $@ build/main.o

test: $(ROM)
	python3 tools/smoketest.py $(ROM)

clean:
	rm -rf build
