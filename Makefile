# VoCoder build entry points. See README.md.
SWIFT ?= swift
FORMAT_PATHS := Package.swift Sources Tests
LOG_FILE := $(HOME)/Library/Logs/VoCoder/vocoder.log

.PHONY: build test pty-test run snapshot-update fmt lint check-deps logs clean

build:
	$(SWIFT) build

test:
	$(SWIFT) test
	@# Smoke check: the executable carries its embedded Info.plist.
	@$(SWIFT) run -q vocoder --version | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+ \([0-9]+\)$$' \
	  || { echo "vocoder --version: embedded Info.plist missing" >&2; exit 1; }

# Drives `vocoder bridge-demo` in a pty: exits, signals, resize, keys, pop-out, crash restore,
# on-screen vs off-screen render. Slower than `make test` (FTXUI's startup wait in a bare pty).
pty-test: build
	python3 -I scripts/bridge-pty-test.py "$$($(SWIFT) build --show-bin-path)/vocoder"

run:
	$(SWIFT) run vocoder $(ARGS)

# Regenerate UI snapshot goldens; review the diff before committing.
snapshot-update:
	VOCODER_SNAPSHOT_UPDATE=1 $(SWIFT) test --filter 'VoCoderUITests|ModuleTests'

fmt:
	$(SWIFT) format format --in-place --parallel --recursive $(FORMAT_PATHS)

lint: check-deps
	$(SWIFT) format lint --strict --parallel --recursive $(FORMAT_PATHS)

# Target dependency rules (Core ← modules, modules never import each other; DESIGN §4.10).
check-deps:
	$(SWIFT) package dump-package | python3 -I scripts/check-deps.py

logs:
	@mkdir -p "$(dir $(LOG_FILE))" && touch "$(LOG_FILE)"
	tail -F "$(LOG_FILE)"

clean:
	$(SWIFT) package clean
	rm -rf .build
