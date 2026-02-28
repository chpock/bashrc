# AGENTS.md

Repository-specific guidance for coding agents working in this repository.

## 1) Project Overview

- This repository is a Bash-focused dotfiles/tooling project.
- Primary source directories:
  - `src/` (raw sources: shell scripts, templated shell scripts, and config files)
  - `functions/` (shell features sourced by generated `bashrc`)
  - `tests/` (script-based tests)
  - `portable/` (portable binary build scripts)
  - `tools/` (standalone independent scripts)
- In `src/`, only `rebuild.sh` is executable as a build step in source checkout.
- Do not run other `src/*` files directly; treat them as sources/templates.
- Running `bash src/rebuild.sh` processes sources and regenerates root artifacts:
  - `bashrc`
  - `tmux.conf.template`
  - `tools.list`
- Root `bashrc` is a generated artifact; use it with Bash `--rcfile` when needed.
- Files in `functions/` are not independent entry-point scripts.
- `functions/*.sh` expect base helpers/functions already loaded in shell and are sourced by generated `bashrc`.
- There is no `package.json`, `pyproject.toml`, or `Makefile` in this repo.
- CI currently includes GitHub Pages deploy in `.github/workflows/gh-pages.yaml`.

## 2) Build, Lint, and Test Commands

Use these commands from repo root.

### Core Build

- Rebuild generated files (`bashrc`, `tools.list`, `tmux.conf.template`):
  - `bash src/rebuild.sh`
- Silent rebuild:
  - `bash src/rebuild.sh silent`
- Note:
  - Do not use `tools/bashrc -build` in a source checkout; it expects an installed layout.
  - In this repository, use `bash src/rebuild.sh [silent]`.

### Tests

- Tests in `tests/` are currently intended for manual runs.
- Do not run tests automatically in a clean environment unless the user explicitly asks.
- Run cut-path test:
  - `bash tests/test-cutpath.sh`
- Run version-compare test (depends on `_vercomp` defined in `src/bashrc.sh`):
  - `bash -lc 'source "src/bashrc.sh" && source "tests/test-vercomp.sh"'`

### Single Test (important)

- Single test file execution is script-based (no test runner abstraction).
- Single tests are manual/opt-in, not part of default automated validation.
- Preferred single-test command:
  - `bash tests/test-cutpath.sh`
- Alternative single-test command for version compare:
  - `bash -lc 'source "src/bashrc.sh" && source "tests/test-vercomp.sh"'`

### Lint / Static Checks

- Syntax check selected scripts:
  - `bash -n src/rebuild.sh tools/bashrc tests/test-cutpath.sh tests/test-vercomp.sh`
- ShellCheck may be available on the machine; if installed, lint changed shell files:
  - `shellcheck src/rebuild.sh tools/bashrc tests/test-cutpath.sh tests/test-vercomp.sh`
- This repo contains many inline `shellcheck disable=...` directives; preserve intent.

### Portable Artifact Builds

- Curl portable build:
  - `bash portable/curl/build.sh`
- Bash portable build:
  - `bash portable/bash/build.sh`
- Vim portable build:
  - `bash portable/vim/build.sh`
- Notes:
  - These scripts invoke Docker automatically if not inside container.
  - They perform package installs and can be long-running.

### CI Evidence

- `.github/workflows/gh-pages.yaml` builds `portable/curl/build.sh` and publishes artifact.
- No dedicated CI lint/test workflow currently exists.

## 3) What Not To Assume

- Do not assume Node/Python build tooling exists.
- Do not assume a unified test framework (Bats, pytest, Jest) exists.
- Do not add new package manager workflows unless user requests it.

## 4) Code Style Conventions (Observed)

Follow established patterns in `src/*.sh`, `functions/*.sh`, `tools/bashrc`, and tests.

### Shell and Script Structure

- Shebang is typically `#!/bin/bash`.
- Scripts commonly enable strict-ish mode:
  - `set -eo pipefail` (common in orchestrator scripts)
  - `set -e` (common in portable build scripts)
- Prefer small functions with focused behavior.
- Use 4-space indentation in function bodies.

### Naming

- Internal helpers frequently use leading underscore:
  - `_hash`, `_is`, `_check`, `_get_url`, `_vercomp`
- Private/internal helpers sometimes use double underscore:
  - `__install_*`, `__git_status`
- Constants and long-lived globals are uppercase:
  - `IAM_HOME`, `LOCAL_TOOLS_FILE_HASH`, `BUILD_DOCKER_IMAGE`
- Local temporaries are lower/mixed case with descriptive names.

### Variables and Scope

- Use `local` for function-scoped variables.
- Quote variable expansions by default: `"$VAR"`.
- Use `printf -v` where assigning formatted output.
- For command existence checks, use helpers or `command -v`.

### Conditionals and Tests

- Prefer POSIX-style test brackets `[ ... ]` in most code.
- Use `[[ ... ]]` selectively for regex/pattern cases when needed.
- Use explicit return paths and status checks.

### Command Invocation Style

- Use `command <tool>` to bypass aliases/functions when intentional.
- Some wrappers intentionally shadow commands (for example `git()` wrapper).
- Respect existing wrappers instead of replacing them ad hoc.

### Error Handling and Messaging

- Existing message helpers:
  - `_warn`, `_err`, `_info`, `_dbg`
- Handle failure paths explicitly and return non-zero on errors.
- Avoid silent failures unless existing pattern intentionally suppresses output.

### ShellCheck Practices

- This codebase uses targeted `shellcheck disable=...` comments with rationale.
- If adding a disable directive, keep it local and explain why.
- Do not broadly disable ShellCheck for entire files.

### Subshells and Side Effects

- Use subshells for context isolation when changing directories.
- Preserve working directory when commands may run from transient paths.
- Be careful with scripts that source `src/bashrc.sh` (it has side effects).

### Text Processing

- Existing code frequently uses `sed`, `awk`, `grep`, `cut`, `tr` for pipelines.
- Match current style for simple stream transformations.
- Keep parsing logic explicit and robust for older environments.

### Portability Considerations

- Repo supports multiple platforms (`linux`, `macos`, `cygwin`, `msys`, `mingw`, `wsl`).
- Prefer compatibility-conscious shell patterns already present in code.
- Avoid introducing GNU-only assumptions without guard/fallback logic.

## 5) Agent Workflow Guidance

- Before edits, inspect neighboring functions for style and naming alignment.
- After edits, run at minimum:
  - `bash -n` on changed scripts
  - run test scripts in `tests/` only when explicitly requested
  - `bash src/rebuild.sh silent` if generated outputs may be affected
- Keep edits minimal and surgical; this repo has many environment-dependent paths.

## 6) Cursor/Copilot Rules

- `.cursorrules`: not present.
- `.cursor/rules/`: not present.
- `.github/copilot-instructions.md`: not present.

If these files are added later, update this section and incorporate those rules.

## 7) High-Risk Areas

- `src/bashrc.sh`: large initialization script with side effects during sourcing.
- `functions/install.sh`: complex installer logic and platform branching.
- `portable/*/build.sh`: network, Docker, package-install side effects.

Prefer incremental changes and verify behavior with targeted commands.
