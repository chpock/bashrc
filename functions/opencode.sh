#!/bin/bash

_has_potentially opencode || return

__OPENCODE_ROOT="$IAM_HOME/tools/opencode"
mkdir -p "$__OPENCODE_ROOT"

__OPENCODE_STDOUT="$__OPENCODE_ROOT/stdout"
__OPENCODE_STDERR="$__OPENCODE_ROOT/stderr"
__OPENCODE_ADDRESS="$__OPENCODE_ROOT/address"
__OPENCODE_PID_FILE="$__OPENCODE_ROOT/pid"
__OPENCODE_SIZE_FILE="$__OPENCODE_ROOT/size"

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
    while true; do
        if ! __opencode_check_pid "$OPENCODE_PID"; then
            rm -f "$__OPENCODE_ADDRESS"
            return 0
        fi
        local CURRENT_SECONDS="$SECONDS"
        local DURATION="$(( CURRENT_SECONDS - START_SECONDS ))"
        if [ "$DURATION" -gt "$MAX_WAIT_TIMEOUT" ]; then
            echo "Timeout while waiting for opencode to stop." >&2
            return 1
        fi
        if [ "$DURATION" -ge 2 ] && [ "$CURRENT_SECONDS" -ne "$LAST_SECONDS" ]; then
            echo "[$DURATION/$MAX_WAIT_TIMEOUT] Waiting for opencode to stop..."
        fi
        LAST_SECONDS="$CURRENT_SECONDS"
        sleep 0.1
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
    opencode serve < /dev/null > "$__OPENCODE_STDOUT" 2> "$__OPENCODE_STDERR" &
    OPENCODE_PID=$!
    disown "$OPENCODE_PID"
    echo "$OPENCODE_PID" > "$__OPENCODE_PID_FILE"
    local MAX_WAIT_TIMEOUT=10 START_SECONDS="$SECONDS"
    local LAST_SECONDS="$START_SECONDS"
    while true; do
        if ! __opencode_check_pid "$OPENCODE_PID"; then
            echo "Failed while waiting for opencode to start." >&2
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
            echo "Timeout while waiting for opencode to start." >&2
            return 1
        fi
        if [ "$DURATION" -ge 2 ] && [ "$CURRENT_SECONDS" -ne "$LAST_SECONDS" ]; then
            echo "[$DURATION/$MAX_WAIT_TIMEOUT] Waiting for opencode to start..."
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
            echo "Failed to cd into $__OPENCODE_ROOT" >&2
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
