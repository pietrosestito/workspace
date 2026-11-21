# Il Nonno e la Coppa rubata - Love2D
LOVE_FILES = conf.lua main.lua lib scenes levels assets

all: build/nonno.love

assets: tools/mkassets.py tools/portrait.py
	python3 tools/mkassets.py

build/nonno.love: assets $(shell find lib scenes levels -type f) conf.lua main.lua
	mkdir -p build
	rm -f $@
	zip -9 -r -q $@ $(LOVE_FILES) -x '*.DS_Store'

run:
	love .

# headless play-through (needs xvfb-run); screenshots go to love's save dir
test:
	SDL_AUDIODRIVER=dummy xvfb-run -a -s "-screen 0 1280x720x24" love . --test

clean:
	rm -rf build

.PHONY: all run test clean
