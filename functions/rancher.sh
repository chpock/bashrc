#!/bin/bash

_has_potentially rancher || return

,rancher() {

    case "$1" in
        update-kubeconfig)
            if [ -z "$2" ]; then
                _info "Update kubeconfig for all clusters ..."
                # shellcheck disable=SC2046
                set -- $(rancher clusters ls --format '{{.Cluster.Name}}')
            else
                set -- "$2"
            fi
            local CLUSTER_NAME BASE_KUBECONFIG_PATH="$_KUBECONFIG_BASE/rancher"
            mkdir -p "$BASE_KUBECONFIG_PATH"
            for CLUSTER_NAME; do
                _info "Update kubeconfig for cluster '%s' ..." "$CLUSTER_NAME"
                rancher cluster kubeconfig "$CLUSTER_NAME" > "$BASE_KUBECONFIG_PATH/$CLUSTER_NAME"
            done
            if [ $# -eq 1 ]; then
                ,kube config "rancher/$1"
            fi
        ;;
        *)
            [ -n "$1" ] && echo "Unknown command '$1'"
            echo "Usage: ,rancher <command>"
            echo
            echo "Available commands:"
            echo "  update-kubeconfig - update kubeconfig"
            return 1
        ;;
    esac

}

__rancher_complete() {

    local __VAR

    COMPREPLY=()

    if [ "$COMP_CWORD" -lt 2 ]; then
        # Disable: Prefer mapfile or read -a to split command output (or quote to avoid splitting). [SC2207]
        # shellcheck disable=SC2207
        COMPREPLY=($(compgen -W "update-kubeconfig" -- "${COMP_WORDS[1]}"))
        return
    fi

    case "${COMP_WORDS[1]}" in
        update-kubeconfig)
            if ! __VAR="$(rancher clusters ls --format '{{.Cluster.Name}}' 2>&1)"; then
                echo
                cprintf -n '~r~ERROR~K~: ~d~%s' "$__VAR"
                COMPREPLY=('~=~=~=~=~=~' '=~=~=~=~=~=')
            else
                # Disable: Prefer mapfile or read -a to split command output (or quote to avoid splitting). [SC2207]
                # shellcheck disable=SC2207
                COMPREPLY=($(compgen -W "$__VAR" -- "${COMP_WORDS[2]}"))
            fi
        ;;
    esac

}

complete -F __rancher_complete ,rancher
