#!/bin/bash


_has tmux || return

,tmux() {
    local CMD="$1"
    local SEP=$'\t'
    local SESSION_BACKUP_FILE="$TMUX_TMPDIR/backup"
    local session_name session_id session_persistent_id session_dir restore_state
    local window_id
    local window_name window_persistent_id current_path
    local active_window_id
    shift

    case "$CMD" in
        _get-id-from-backup)
            if [ -e "$BACKUP_FILE_IDS" ]; then
                local current_session_name
                current_session_name="$(tmux display-message -p '#S')"
                while IFS="$SEP" read -r session_name session_id; do
                    if [ "$session_name" = "$current_session_name" ]; then
                        echo "$session_id"
                        return 0
                    fi
                done < "$BACKUP_FILE_IDS"
            fi
            return 1
            ;;
        save)
            local window_index
            while IFS="$SEP" read -r session_name session_id session_persistent_id restore_state; do
                echo "${session_name}${SEP}${session_persistent_id}"
                if [ "$restore_state" = pending ] || [ "$restore_state" = restoring ]; then
                    # Keep the previous window backup while this session only has
                    # its temporary restore window.
                    continue
                fi
                session_dir="$TMUX_TMPDIR/id-$session_persistent_id"
                active_window_id="$(command tmux display-message -t "$session_id" -p -F '#{window_id}' 2>/dev/null)"
                rm -f "$session_dir/backup_active"
                while IFS="$SEP" read -r window_index window_name window_id current_path; do
                    [ "$window_index" != 0 ] || continue
                    [ "$(command tmux show -w -t "$window_id" -v '@restore-dummy' 2>/dev/null)" != "1" ] || continue
                    window_persistent_id="$(command tmux show -w -t "$window_id" -v '@persistent-id')"
                    echo "${window_name}${SEP}${window_persistent_id}${SEP}${current_path}"
                    if [ "$window_id" = "$active_window_id" ]; then
                        echo "$window_persistent_id" > "$session_dir/backup_active"
                    fi
                done \
                    < <(command tmux list-windows -t "$session_id" -F "#{window_index}${SEP}#{window_name}${SEP}#{window_id}${SEP}#{pane_current_path}") \
                    > "$session_dir/backup"
            done \
                < <(command tmux list-sessions -F "#{session_name}${SEP}#{session_id}${SEP}#{_TMUX_SESSION_ID}${SEP}#{@restore-state}") \
                > "$SESSION_BACKUP_FILE"
            ;;
        restore)
            local dummy_window_id dummy_pane_id bootstrap_window_id session_info
            local dummy_hook
            local tmp_session_id tmp_session_persistent_id
            local cols lines known_sessions

            # Restore only the session skeletons here. Window materialization is
            # deliberately deferred until restore-single-session is called.
            [ -e "$SESSION_BACKUP_FILE" ] || return 0
            # We don't use filter feature to find existing sessions as it is only
            # available in tmux v3.3+.
            known_sessions="$(command tmux list-sessions -F "#{session_id}${SEP}#{_TMUX_SESSION_ID}" 2>/dev/null || true)"
            cols="$(tput cols 2>/dev/null)" || cols="-"
            lines="$(tput lines 2>/dev/null)" || lines="-"
            while IFS="$SEP" read -r session_name session_persistent_id; do
                unset session_id
                while IFS="$SEP" read -r tmp_session_id tmp_session_persistent_id; do
                    if [ "$tmp_session_persistent_id" = "$session_persistent_id" ]; then
                        session_id="$tmp_session_id"
                        break
                    fi
                done <<< "$known_sessions"
                [ -z "$session_id" ] || continue

                echo "[TMUX] restore session: $session_name"
                # tmux 3.1+ supports setting the environment during
                # new-session, but older versions do not. Create a bootstrap
                # window first, then set the session identity explicitly.
                session_info="$(
                    SSH_PUB_KEY="$SSH_PUB_KEY" \
                    _GIT_USER_EMAIL="$_GIT_USER_EMAIL" \
                    _GIT_USER_NAME="$_GIT_USER_NAME" \
                    tmux new-session -d -x "$cols" -y "$lines" -s "$session_name" -P -F "#{session_id}${SEP}#{window_id}" -n '__restore-bootstrap__' 'sleep infinity'
                )" || {
                    _warn "could not create tmux session '%s'" "$session_name"
                    continue
                }
                session_id="${session_info%%"$SEP"*}"
                bootstrap_window_id="${session_info#*"$SEP"}"
                if [ -z "$session_id" ] || [ -z "$bootstrap_window_id" ]; then
                    _warn "could not get IDs of new tmux session '%s'" "$session_name"
                    continue
                fi

                # Mark the session pending before creating its dummy window.
                # The pending state protects the old backup from autosave.
                session_dir="$TMUX_TMPDIR/id-$session_persistent_id"
                mkdir -p "$session_dir"
                command tmux set-env -t "$session_id" _TMUX_SESSION_ID "$session_persistent_id"
                command tmux set -t "$session_id" '@restore-state' pending
                echo "$session_id" > "$session_dir/sid"

                if ! dummy_window_id="$(tmux new-window -d -t "$session_id" -n '__dummy__' -P -F '#{window_id}')"; then
                    _warn "could not create dummy window for tmux session '%s'" "$session_name"
                    command tmux kill-session -t "$session_id" 2>/dev/null || true
                    continue
                fi
                dummy_pane_id="$(command tmux list-panes -t "$dummy_window_id" -F '#{pane_id}')"
                # Keep the attach trigger scoped to this pending session. The
                # hook only sends Enter; the ordinary bashrc in the dummy pane
                # performs the actual one-session restore.
                dummy_hook="if-shell -F \"#{==:#{@restore-state},pending}\" \"send-keys -t $dummy_pane_id Enter\""
                if [ -z "$dummy_pane_id" ] \
                    || ! command tmux set -w -t "$dummy_window_id" '@restore-dummy' 1 \
                    || ! command tmux set-hook -t "$session_id" client-attached "$dummy_hook" \
                    || ! command tmux set-hook -t "$session_id" client-session-changed "$dummy_hook" \
                    || ! command tmux kill-window -t "$bootstrap_window_id"; then
                    _warn "could not finalize dummy window for tmux session '%s'" "$session_name"
                    command tmux kill-session -t "$session_id" 2>/dev/null || true
                    continue
                fi
            done < "$SESSION_BACKUP_FILE"
            ;;
        restore-single-session)
            (
                # Run this operation in an isolated shell. Explicit failure
                # exits and set -e both reach the EXIT trap below, which rolls
                # the session back without affecting the caller.
                set -e

                # This mode materializes the windows of one pending session. The
                # argument is the persistent session ID, not tmux's runtime ID.
                session_persistent_id="$1"
                [ -n "$session_persistent_id" ] || {
                    _warn "cannot restore tmux session without persistent ID"
                    exit 1
                }
                [ -e "$SESSION_BACKUP_FILE" ] || {
                    _warn "tmux session backup does not exist: %s" "$SESSION_BACKUP_FILE"
                    exit 1
                }

                # Resolve the persistent ID to the saved name for diagnostics.
                unset session_name
                while IFS="$SEP" read -r tmp_session_name tmp_session_persistent_id; do
                    [ "$tmp_session_persistent_id" = "$session_persistent_id" ] || continue
                    session_name="$tmp_session_name"
                    break
                done < "$SESSION_BACKUP_FILE"
                [ -n "$session_name" ] || {
                    _warn "tmux session with persistent ID '%s' is not in the backup" "$session_persistent_id"
                    exit 1
                }

                # Resolve the same persistent ID to the currently live tmux session.
                unset session_id
                while IFS="$SEP" read -r tmp_session_id tmp_session_persistent_id; do
                    if [ "$tmp_session_persistent_id" = "$session_persistent_id" ]; then
                        session_id="$tmp_session_id"
                        break
                    fi
                done < <(command tmux list-sessions -F "#{session_id}${SEP}#{_TMUX_SESSION_ID}" 2>/dev/null || true)
                [ -n "$session_id" ] || {
                    _warn "tmux session '%s' with persistent ID '%s' does not exist" "$session_name" "$session_persistent_id"
                    exit 1
                }

                # Only a pending session may be materialized. The restoring state
                # prevents two attach events from restoring the same session twice.
                restore_state="$(command tmux show -t "$session_id" -v '@restore-state' 2>/dev/null || true)"
                if [ "$restore_state" != pending ]; then
                    [ "$restore_state" = restoring ] && exit 1
                    exit 0
                fi

                session_dir="$TMUX_TMPDIR/id-$session_persistent_id"
                [ -e "$session_dir/backup" ] || {
                    _warn "tmux session '%s' has no window backup: %s" "$session_name" "$session_dir/backup"
                    exit 1
                }

                # Roll back every incomplete restore. The trap removes the marker
                # used by new panes and changes restoring back to pending. It
                # checks tmux's actual state, so it is also harmless after a
                # successful state cleanup.
                # shellcheck disable=SC2317,SC2329 # Called indirectly by the EXIT trap.
                restore_cleanup() {
                    rm -f "$session_dir/mode-restore" 2>/dev/null || true
                    if [ "$(command tmux show -t "$session_id" -v '@restore-state' 2>/dev/null || true)" = restoring ]; then
                        command tmux set -t "$session_id" '@restore-state' pending 2>/dev/null || true
                    fi
                }
                trap restore_cleanup EXIT
                if ! command tmux set -t "$session_id" '@restore-state' restoring; then
                    exit 1
                fi

                # Build the set of already restored real windows. The dummy is
                # intentionally excluded because it has no persistent window ID.
                unset active_window_id active_window_persistent_id
                if [ -e "$session_dir/backup_active" ]; then
                    if ! active_window_persistent_id="$(< "$session_dir/backup_active")"; then
                        exit 1
                    fi
                fi
                unset known_windows
                if ! window_list="$(command tmux list-windows -t "$session_id" -F '#{window_id}' 2>/dev/null)"; then
                    exit 1
                fi
                while read -r window_id; do
                    [ "$(command tmux show -w -t "$window_id" -v '@restore-dummy' 2>/dev/null)" != "1" ] || continue
                    window_persistent_id="$(command tmux show -w -t "$window_id" -v '@persistent-id' 2>/dev/null || true)"
                    [ -n "$window_persistent_id" ] || continue
                    known_windows+="${SEP}${window_persistent_id}"
                    [ "$window_persistent_id" != "$active_window_persistent_id" ] || active_window_id="$window_id"
                done <<< "$window_list"
                known_windows+="${SEP}"

                # Read the backup before creating panes so a read error also
                # follows the rollback path instead of looking like an empty restore.
                if ! session_backup="$(< "$session_dir/backup")"; then
                    exit 1
                fi

                # Tell the normal bashrc in newly created panes to wait until the
                # persistent window ID is assigned below.
                if ! echo > "$session_dir/mode-restore"; then
                    exit 1
                fi
                expected_windows=0
                failed_windows=0
                while IFS="$SEP" read -r window_name window_persistent_id current_path; do
                    [ -n "$window_persistent_id" ] || continue
                    expected_windows=$(( expected_windows + 1 ))
                    # Check if the current window is in the list of existing windows.
                    [ "$known_windows" = "${known_windows#*"${SEP}$window_persistent_id${SEP}"}" ] || continue
                    echo "[TMUX] restore window '$window_name' with path '$current_path' (session: $session_name)"
                    if ! window_id="$(tmux new-window -d -t "$session_id" -c "$current_path" -P -F '#{window_id}')"; then
                        _warn "could not restore the window '%s' with current path '%s'" "$window_name" "$current_path"
                        failed_windows=$(( failed_windows + 1 ))
                        continue
                    fi
                    if ! command tmux set -w -t "$window_id" '@persistent-id' "$window_persistent_id"; then
                        _warn "could not assign persistent ID '%s' to restored window '%s'" "$window_persistent_id" "$window_name"
                        command tmux kill-window -t "$window_id" 2>/dev/null || true
                        failed_windows=$(( failed_windows + 1 ))
                        continue
                    fi
                    [ "$window_persistent_id" != "$active_window_persistent_id" ] || active_window_id="$window_id"
                done <<< "$session_backup"

                # Explicitly report expected window failures; the EXIT trap
                # performs the common rollback before this subshell exits.
                if [ "$expected_windows" -eq 0 ] || [ "$failed_windows" -ne 0 ]; then
                    if [ "$expected_windows" -eq 0 ]; then
                        _warn "tmux session '%s' has no restorable windows in %s" "$session_name" "$session_dir/backup"
                    else
                        _warn "tmux session '%s' was only partially restored; failed windows: %s" "$session_name" "$failed_windows"
                    fi
                    exit 1
                fi

                # Remove the state before removing hooks. If hook cleanup fails,
                # a leftover hook is harmless because it only acts for pending sessions.
                if [ -n "$active_window_id" ] && ! command tmux select-window -t "${session_id}:${active_window_id}"; then
                    exit 1
                fi
                if ! command tmux set -u -t "$session_id" '@restore-state'; then
                    exit 1
                fi
                command tmux set-hook -u -t "$session_id" client-attached
                command tmux set-hook -u -t "$session_id" client-session-changed
                exit 0
            )
            ;;
        autosave)
            # Backup sessions every 10th invocation
            __TMUX_BACKUP_COUNTER=$(( __TMUX_BACKUP_COUNTER + 1 ))
            if [ $__TMUX_BACKUP_COUNTER -ge 10 ]; then
                ,tmux save
                __TMUX_BACKUP_COUNTER=0
            fi
            ;;
        memory)
            local MAX_LEN_SIZE MAX_LEN_SESSION
            # Find the longest number of bytes
            MAX_LEN_SIZE="$(tmux list-panes -a -F '#{history_bytes}' \
                | awk 'length > maxlen { maxlen = length } END { print maxlen }')"
            # Find the longest session name
            MAX_LEN_SESSION="$(tmux list-sessions -F '#S' \
                | awk 'length > maxlen { maxlen = length } END { print maxlen }')"
            tmux list-panes -a -F \
                "#{p$(( MAX_LEN_SIZE + 1 )):history_bytes} [#{p$(( MAX_LEN_SESSION + 1 )):session_name}] Win: ###{window_index} (lines: #{history_size}/#{history_limit})" \
                | sort --numeric-sort --reverse
            ;;
        clean)
            local ID
            tmux list-panes -a -F '#{pane_id}' | while read -r ID; do
                tmux clear-history -t "$ID"
            done
            ;;
        *)
            echo "Unknown cmd: '$CMD'"
            return 1
            ;;
    esac
}

_tmux_generate_conf() {

    local TMUX_CONF_TEMPLATE="$IAM_HOME/tmux.conf.template"
    local TMUX_CONF="$IAM_HOME/tmux.conf"

    # return if there is no tmux.conf template
    [ -e "$TMUX_CONF_TEMPLATE" ] || return 0
    # return if tmux.conf exists and its timestamp is newer than the tmux.conf template
    [ -e "$TMUX_CONF" ] && [ "$TMUX_CONF" -nt "$TMUX_CONF_TEMPLATE" ] && return 0 || :

    # strip beta prefix for versions like '3.0a', '3.1c', etc.
    local ver
    ver="$(command tmux -V | sed -E -e 's/^.*[[:space:]][^[:digit:]]*//' -e 's/[^[:digit:]]*$//')"

    local min_ver max_ver line blank
    unset blank
    while IFS= read -r line; do
        [ -z "$line" ] && [ -n "$blank" ] && continue || true
        unset min_ver max_ver
        case "$line" in
            [0-9].[0-9][+-]:*) min_ver="${line:0:3}"; line="${line:5}" ;;
            -[0-9].[0-9]:*)    max_ver="${line:1:3}"; line="${line:5}" ;;
            [0-9].[0-9]-[0-9].[0-9]:*)
                min_ver="${line:0:3}"
                max_ver="${line:4:3}"
                line="${line:8}"
                ;;
        esac
        [ -z "$min_ver" ] || { _vercomp "$min_ver" '<=' "$ver" || continue; }
        [ -z "$max_ver" ] || { _vercomp "$max_ver" '>=' "$ver" || continue; }
        # Disable: Note that A && B || C is not if-then-else. C may run when A is true. [SC2015]
        # shellcheck disable=SC2015
        [ -z "$line" ] && blank=1 || unset blank
        echo "$line"
    done < "$TMUX_CONF_TEMPLATE" > "$TMUX_CONF"

}

__TMUX_FUNCTIONS_AVAILABLE=1

complete -W 'save restore restore-single-session memory clean' ,tmux
