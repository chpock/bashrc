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
# Don't use custom bashrc when:
# - shell level is not "1" (for example, for commands and shell from Far Manager)
# - shell is not interactive
# - BASH_EXECUTION_STRING exists (when bash is executed with `-c ...`)
# - any of stdin/stdout/stderr is not a tty
# - custom bashrc doesn't exist or isn't readable
#
# In a regular shell, our custom bashrc always sets TMUX_TMPDIR to use our tmux server.
# If we are already inside tmux but TMUX_TMPDIR is unset, we treat that environment as externally
# managed. This can happen when another application, such as Neovim, creates its own tmux sessions.
# In that case, don't launch the custom bashrc.
RC=/w/projects/bashrc/bashrc
if [[ $SHLVL -eq 1 &&
        $- == *i* &&
        ! -v BASH_EXECUTION_STRING &&
        -t 0 && -t 1 && -t 2 &&
        -r $RC ]] &&
    [[ -z ${TMUX:-} || -v TMUX_TMPDIR ]]; then
    exec "$BASH" --rcfile "$RC" -i
fi
unset RC
```

Replace `/some/dir` with the actual path where you cloned the repository.

## Requirements

- Bash 4.x or later
- Linux, macOS, WSL, or similar Unix-like environment

## License

See repository for details.
