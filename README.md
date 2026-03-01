# bashrc

Personal bash shell environment configuration.

## Description

This project provides a customized bash shell environment with personalized settings, aliases, functions, and tooling.

## Installation

Clone this repository to your preferred directory:

```bash
mkdir -p /some/dir
cd /some/dir
git clone https://github.com/chpock/bashrc.git .
```

Add the following line to your `~/.bashrc`:

```bash
RC=some/dir/bashrc && [[ $- == *i* ]] && [ -r "$RC" ] && [ "$SHLVL" -eq 1 ] && exec "$BASH" --rcfile "$RC" -i || unset RC
```

Replace `/some/dir` with the actual path where you cloned the repository.

## Requirements

- Bash 4.x or later
- Linux, macOS, WSL, or similar Unix-like environment

## License

See repository for details.
