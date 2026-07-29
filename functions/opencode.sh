#!/bin/bash

_has_potentially opencode || return

__OPENCODE_ROOT="$IAM_HOME/tools/opencode"
mkdir -p "$__OPENCODE_ROOT"

__OPENCODE_STDOUT="$__OPENCODE_ROOT/stdout"
__OPENCODE_STDERR="$__OPENCODE_ROOT/stderr"
__OPENCODE_ADDRESS="$__OPENCODE_ROOT/address"
__OPENCODE_PID_FILE="$__OPENCODE_ROOT/pid"
__OPENCODE_SIZE_FILE="$__OPENCODE_ROOT/size"

__OPENCODE_AUTH_FILE="${XDG_DATA_HOME:-$HOME/.local/share}/opencode/auth.json"
__OPENCODE_ACCOUNTS_FILE="${XDG_DATA_HOME:-$HOME/.local/share}/opencode/accounts.json"

,opencode() {
    if [ -z "$1" ]; then
        _info "Usage: ,opencode account-set|account-refresh <provider> <account_id>"
        return
    fi
    case "$1" in
        account-set-active)
            shift
            _,opencode_account_set_active "$@" || return $?
            ;;
        account-rename-active)
            shift
            _,opencode_account_rename_active "$@" || return $?
            ;;
        *)
            _err "Unknown command '%s'" "$1"
            return 1
            ;;
    esac
}

_,opencode_account_set_active() {
    if [ -z "$1" ]; then
        _info "Usage: ,opencode account-set-active <provider> <account_id>"
        return 0
    fi
    __opencode_ensure_accounts_file || return 1
}

_,opencode_account_rename_active() {
    if [ -z "$1" ]; then
        _info "Usage: ,opencode account-rename-active <provider> [<new_account_id>]"
        return 0
    fi
    local PROVIDER="$1"
    __opencode_ensure_accounts_file || return 1
    if ! jq -e --arg key "$PROVIDER" 'has($key)' "$__OPENCODE_ACCOUNTS_FILE" >/dev/null; then
        _err "there is no provider '%s', known provider(s): %s" \
            "$PROVIDER" "$(__opencode_get_providers | sed 's/ /, /g')"
    fi
}

__opencode_ensure_accounts_file() {
    if [ ! -r "$__OPENCODE_AUTH_FILE" ]; then
        if [ -z "$__OPENCODE_SILENT" ]; then
            _err "could not find or read opencode auth file: %s" "$__OPENCODE_AUTH_FILE"
        fi
        return 1
    fi
    if [ ! -e "$__OPENCODE_ACCOUNTS_FILE" ]; then
        jq 'with_entries(
            .value = [
                {
                    accountId: "default",
                    isActive: true,
                }
            ]
        )' "$__OPENCODE_AUTH_FILE" > "$__OPENCODE_ACCOUNTS_FILE"
        return 0
    fi
    local ACTUAL_PROVIDERS CURRENT_PROVIDERS TEMP_ACCOUNTS_FILE
    # keys - sorts keys so we can just compare lists as strings
    ACTUAL_PROVIDERS="$(__opencode_get_providers)"
    CURRENT_PROVIDERS="$(jq -r 'keys | join(" ")' "$__OPENCODE_AUTH_FILE")"
    [ "$ACTUAL_PROVIDERS" != "$CURRENT_PROVIDERS" ] || return 0
    # add missing providers
    TEMP_ACCOUNTS_FILE="$(mktemp)"
    if ! jq -s '
            .[0] as $source
            | .[1] as $result
            | (
                $source
                | with_entries(
                    .value = [
                        {
                            accountId: "default",
                            isActive: true
                        }
                    ]
                    )
                ) + $result
        ' "$__OPENCODE_AUTH_FILE" "$__OPENCODE_ACCOUNTS_FILE" > "$TEMP_ACCOUNTS_FILE"
    then
        rm -f "$TEMP_ACCOUNTS_FILE"
        if [ -z "$__OPENCODE_SILENT" ]; then
            _err "something wrong happened while adding new providers to the account file"
        fi
        return 1
    fi
    mv -f "$TEMP_ACCOUNTS_FILE" "$__OPENCODE_ACCOUNTS_FILE"
}

__opencode_get_providers() {
    jq -r 'keys | join(" ")' "$__OPENCODE_ACCOUNTS_FILE"
}

__,opencode_complete() {

    local __VAR

    COMPREPLY=()

    if [ "$COMP_CWORD" -lt 2 ]; then
        # Disable: Prefer mapfile or read -a to split command output (or quote to avoid splitting). [SC2207]
        # shellcheck disable=SC2207
        COMPREPLY=($(compgen -W "account-set-active account-rename-active" -- "${COMP_WORDS[1]}"))
        return
    fi

    # case "${COMP_WORDS[1]}" in
    #     update-kubeconfig)
    #         if ! __VAR="$(rancher clusters ls --format '{{.Cluster.Name}}' 2>&1)"; then
    #             echo
    #             cprintf -n '~r~ERROR~K~: ~d~%s' "$__VAR"
    #             COMPREPLY=('~=~=~=~=~=~' '=~=~=~=~=~=')
    #         else
    #             # Disable: Prefer mapfile or read -a to split command output (or quote to avoid splitting). [SC2207]
    #             # shellcheck disable=SC2207
    #             COMPREPLY=($(compgen -W "$__VAR" -- "${COMP_WORDS[2]}"))
    #         fi
    #     ;;
    # esac

}

complete -F __,opencode_complete ,opencode

__opencode_check_pid() {
    local OPENCODE_PID="$1"
    if [ -z "$OPENCODE_PID" ] || ! kill -0 "$OPENCODE_PID" >/dev/null 2>&1; then
        rm -f "$__OPENCODE_PID_FILE"
        return 1
    fi
    local OPENCODE_CMD
    OPENCODE_CMD="$(ps -p "$OPENCODE_PID" -o comm= 2>/dev/null)"
    OPENCODE_CMD="${OPENCODE_CMD##*/}"
    if [ "$OPENCODE_CMD" != "opencode" ]; then
        rm -f "$__OPENCODE_PID_FILE"
        return 1
    fi
    return 0
}

__opencode_get_pid() {
    local _OPENCODE_PID _OPENCODE_CMD
    if [ -f "$__OPENCODE_PID_FILE" ]; then
        read -r _OPENCODE_PID < "$__OPENCODE_PID_FILE"
        __opencode_check_pid "$_OPENCODE_PID" || unset _OPENCODE_PID
    fi
    if [ -n "$1" ]; then
        printf -v "$1" '%s' "$_OPENCODE_PID"
    else
        [ -n "$_OPENCODE_PID" ] && return 0 || return 1
    fi
}

__opencode_stop_server() {
    local OPENCODE_PID
    __opencode_get_pid OPENCODE_PID
    [ -n "$OPENCODE_PID" ] || return 0
    __opencode_check_pid "$OPENCODE_PID" || return 0
    kill "$OPENCODE_PID"
    local MAX_WAIT_TIMEOUT=10 START_SECONDS="$SECONDS"
    local LAST_SECONDS="$START_SECONDS"
    local HARD_KILL=0
    while true; do
        if ! __opencode_check_pid "$OPENCODE_PID"; then
            rm -f "$__OPENCODE_ADDRESS"
            return 0
        fi
        local CURRENT_SECONDS="$SECONDS"
        local DURATION="$(( CURRENT_SECONDS - START_SECONDS ))"
        if [ "$DURATION" -gt "$MAX_WAIT_TIMEOUT" ]; then
            _err "Timeout while waiting for opencode to stop." >&2
            return 1
        fi
        if [ "$DURATION" -ge 2 ] && [ "$CURRENT_SECONDS" -ne "$LAST_SECONDS" ]; then
            _info "[$DURATION/$MAX_WAIT_TIMEOUT] Waiting for opencode to stop..."
        fi
        LAST_SECONDS="$CURRENT_SECONDS"
        if [ "$DURATION" -ge 5 ] && [ "$HARD_KILL" -eq 0 ]; then
            _info "Trying to hard-kill opencode process..."
            kill -9 "$OPENCODE_PID"
            HARD_KILL=1
        else
            sleep 0.1
        fi
    done
}

__opencode_get_bin_size() {
    local OPENCODE_BIN
    OPENCODE_BIN="$(command -v opencode)"
    _get_size "$OPENCODE_BIN"
}

__opencode_check_bin_size() {
    [ -f "$__OPENCODE_SIZE_FILE" ] || return 1
    local OLD_OPENCODE_SIZE NEW_OPENCODE_SIZE
    read -r OLD_OPENCODE_SIZE < "$__OPENCODE_SIZE_FILE"
    NEW_OPENCODE_SIZE="$(__opencode_get_bin_size)"
    [ "$OLD_OPENCODE_SIZE" = "$NEW_OPENCODE_SIZE" ] && return 0 || return 1
}

__opencode_start_server() {
    local OPENCODE_PID
    __opencode_stop_server || return 1
    rm -f "$__OPENCODE_STDOUT" "$__OPENCODE_STDERR" "$__OPENCODE_ADDRESS"
    __opencode_get_bin_size > "$__OPENCODE_SIZE_FILE"
    # Run opencode in subshell. We get 2 benefits from this:
    # 1. No need to swap monitor mode for shell (using 'set +m'/'set -m'). Monitor mode
    # for the interactive shell prints the PID of the launched process.
    # 1. No need to call 'disown $!'
    (
        opencode serve < /dev/null > "$__OPENCODE_STDOUT" 2> "$__OPENCODE_STDERR" &
        echo "$!" > "$__OPENCODE_PID_FILE"
    )
    __opencode_get_pid OPENCODE_PID
    if [ -z "$OPENCODE_PID" ]; then
        _err "Failed to start opencode server."
        return 1
    fi
    local MAX_WAIT_TIMEOUT=10 START_SECONDS="$SECONDS"
    local LAST_SECONDS="$START_SECONDS"
    while true; do
        if ! __opencode_check_pid "$OPENCODE_PID"; then
            _err "Failed while waiting for opencode to start." >&2
            return 1
        fi
        while read -r LINE; do
            if [ "${LINE#opencode server listening on}" != "$LINE" ]; then
                echo "${LINE##* }" > "$__OPENCODE_ADDRESS"
                return 0
            fi
        done < "$__OPENCODE_STDOUT"
        local CURRENT_SECONDS="$SECONDS"
        local DURATION="$(( CURRENT_SECONDS - START_SECONDS ))"
        if [ "$DURATION" -gt "$MAX_WAIT_TIMEOUT" ]; then
            _err "Timeout while waiting for opencode to start." >&2
            return 1
        fi
        if [ "$DURATION" -ge 2 ] && [ "$CURRENT_SECONDS" -ne "$LAST_SECONDS" ]; then
            _info "[$DURATION/$MAX_WAIT_TIMEOUT] Waiting for opencode to start..."
        fi
        LAST_SECONDS="$CURRENT_SECONDS"
        sleep 0.1
    done
}

__opencode_get_address() {
    local _OPENCODE_SERVER_ADDRESS IS_ALIVE=0
    if [ -f "$__OPENCODE_ADDRESS" ] && __opencode_get_pid; then
        if __opencode_check_bin_size; then
            IS_ALIVE=1
        else
            _info "The opencode binary has changed. It should be restarted."
            if ! __opencode_stop_server; then
                printf -v "$1" ''
                return
            fi
        fi
    fi
    if [ "$IS_ALIVE" -eq 1 ] || __opencode_start_server; then
        read -r _OPENCODE_SERVER_ADDRESS < "$__OPENCODE_ADDRESS"
    fi
    printf -v "$1" '%s' "$_OPENCODE_SERVER_ADDRESS"
}

__opencode_request() {
    local OPENCODE_MODEL="$1"
    shift
    # local OPENCODE_VARIANT="$1"
    # shift
    local OPENCODE_PROMPT
    if [ "$#" -gt 0 ]; then
        printf -v OPENCODE_PROMPT '%s' "$*"
    elif [ ! -t 0 ]; then
        OPENCODE_PROMPT="$(cat)"
    fi
    if [ -z "$OPENCODE_PROMPT" ]; then
        _info "Nothing to ask."
        return
    fi
    local OPENCODE_SERVER_ADDRESS
    __opencode_get_address OPENCODE_SERVER_ADDRESS
    [ -n "$OPENCODE_SERVER_ADDRESS" ] || return
    (
        if ! cd "$__OPENCODE_ROOT"; then
            _err "Failed to cd into $__OPENCODE_ROOT" >&2
            exit 1
        fi
        TEMP_RESPONSE="$(mktemp)"
        # --variant "$OPENCODE_VARIANT"
        set -- \
            --dir "$__OPENCODE_ROOT" \
            --format json \
            --model "$OPENCODE_MODEL" \
            --attach "$OPENCODE_SERVER_ADDRESS"
        opencode run "$@" "$OPENCODE_PROMPT" > "$TEMP_RESPONSE" && RC=0 || RC=$?
        if [ "$RC" -ne 0 ]; then
            _err "Something went wrong in opencode. The output is:" >&2
            cat "$TEMP_RESPONSE" >&2
        elif ! _has jq; then
            _warn "jq is not installed. Raw output will be shown. The session will not be cleaned up."
            cat "$TEMP_RESPONSE"
        else
            SESSION_ID="$(jq -r 'select(.type == "step_start") | .sessionID' "$TEMP_RESPONSE")"
            if [ "${SESSION_ID#ses_}" = "$SESSION_ID" ]; then
                _err "Could not retrieve session id from opencode response. Got the following string: %s" "$SESSION_ID" >&2
                echo "Raw output:" >&2
                cat "$TEMP_RESPONSE" >&2
                RC=1
            else
                TEXT="$(jq -r 'select(.type == "text") | .part.text' "$TEMP_RESPONSE")"
                if [ -z "$TEXT" ] || [ "$TEXT" = "null" ]; then
                    _err "Could not retrieve text from opencode response." >&2
                    echo "Raw output:" >&2
                    cat "$TEMP_RESPONSE" >&2
                    RC=1
                elif _has glow; then
                    echo "$TEXT" | glow -w 120
                else
                    _warn "glow is not installed. Text output will not be formatted."
                    echo "$TEXT"
                fi
                if ! SESSION_DELETE_OUTPUT="$(opencode session delete "$SESSION_ID" 2>&1)"; then
                    _err "Error happened during session removal." >&2
                    echo "$SESSION_DELETE_OUTPUT" >&2
                    RC=1
                fi
            fi
        fi
        rm -f "$TEMP_RESPONSE"
        exit "$RC"
    )
}

q() {
    if [ "$1" = "-restart" ]; then
        shift
        __opencode_stop_server
    fi
    __opencode_request opencode-go/minimax-m2.7 "$@"
}

qq() {
    if [ "$1" = "-restart" ]; then
        shift
        __opencode_stop_server
    fi
    # __opencode_request opencode-go/kimi-k2.5 "$@"
    __opencode_request openai/gpt-5.4 "$@"
}
