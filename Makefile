.PHONY: check build test

# Quality gate: shared by the Claude Code Stop hook and the CI `check` job.
check: build test

# Builds every target, including the app and test targets (typecheck).
build:
	swift build --build-tests

test:
	swift test --skip-build
