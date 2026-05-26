#!/bin/bash

_has_potentially kubectl || return

k() {

    _maybe_local "kubectl"

    # Silently install/check kubectl plugins
    _maybe_local "kubectl-browse_pvc" >/dev/null 2>&1
    _maybe_local "kubectl-whoami" >/dev/null 2>&1
    _maybe_local "kubectl-pod_lens" >/dev/null 2>&1
    _maybe_local "kubectl-node_shell" >/dev/null 2>&1
    _maybe_local "kubectl-apidocs" >/dev/null 2>&1
    _maybe_local "kubectl-df_pv" >/dev/null 2>&1
    _maybe_local "kubectl-get_all" >/dev/null 2>&1
    _maybe_local "kubectl-glance" >/dev/null 2>&1
    _maybe_local "kubectl-curl" >/dev/null 2>&1

    [ -z "$__KUBECTL_KUBECOLOR" ] \
        && [ -n "$__INSTALL_FUNCTIONS_AVAILABLE" ] \
        && _check _is_install_available "kubecolor" \
        && ,install "kubecolor" \
        && __KUBECTL_KUBECOLOR=1 \
        || :

    [ -n "$__KUBECTL_KUBECOLOR" ] || __KUBECTL_KUBECOLOR=0

    if [ "$__KUBECTL_KUBECOLOR" = "1" ]; then
        env KUBECOLOR_OBJ_FRESH="2h" kubecolor "$@"
    else
        command kubectl "$@"
    fi

}

,kube() {

    local __K8S_CONF
    local KUBECONFIG_DEFAULT="$_KUBECONFIG_BASE/default"

    if [ -n "$1" ] && ! _has kubectl; then
        _err 'kubectl command is not available in this environment'
        return 1
    fi

    case "$1" in
        on)
            touch "$IAM_HOME/state/on_kube"
        ;;
        off)
            rm -f "$IAM_HOME/state/on_kube"
        ;;
        set-default-config)
            if [ -z "$KUBECONFIG" ]; then
                _err "KUBECONFIG env variable is unset."
                return 1
            elif [ "$KUBECONFIG" = "$KUBECONFIG_DEFAULT" ]; then
                _err "KUBECONFIG is default already: %s" "$KUBECONFIG"
                return 1
            fi
            local LINK="${KUBECONFIG#"$_KUBECONFIG_BASE"/}"
            ln -sf "$LINK" "$KUBECONFIG_DEFAULT"
            ,kube config default
        ;;
        config)
            if [ -z "$2" ]; then
                _err 'the kubeconfig is not specified'
                echo
                echo "Usage: ,kube config <kubeconfig file>"
                return 1
            fi
            __K8S_CONF="$2"
            if [ "${DIR:0:1}" != "/" ]; then
                __K8S_CONF="$_KUBECONFIG_BASE/$__K8S_CONF"
            fi
            if [ ! -e "$__K8S_CONF" ]; then
                _err "the specified kubeconfig file doesn't exist: '%s'" "$__K8S_CONF"
                return 1
            elif [ ! -f "$__K8S_CONF" ]; then
                _err "the specified kubeconfig is not a file: '%s'" "$__K8S_CONF"
                return 1
            fi
            if [ "$__K8S_CONF" = "$KUBECONFIG_DEFAULT" ]; then
                _env_unset KUBECONFIG
                KUBECONFIG="$KUBECONFIG_DEFAULT"
                export KUBECONFIG
            else
                _env_set KUBECONFIG="$__K8S_CONF"
            fi
        ;;
        ns)
            if [ -z "$2" ]; then
                _err "the namespace is not specified"
                echo
                echo "Usage: ,kube ns <namespace>"
                return 1
            fi
            kubectl config set-context "$(kubectl config current-context)" --namespace "$2"
        ;;
        context)
            if [ -z "$2" ]; then
                _err "the context is not specified"
                echo
                echo "Usage: ,kube context <context>"
                return 1
            fi
            kubectl config use-context "$2"
        ;;
        events)
            shift
            kubectl get events --sort-by='.metadata.creationTimestamp' "$@"
        ;;
        *)
            [ -n "$1" ] && echo "Unknown command '$1'"
            echo "Usage: ,kube <command>"
            echo
            echo "Available commands:"
            echo "  conf   - set the current kubeconfig"
            echo "  ns     - set the current namespace"
            echo "  on     - turn on k8s bash prompt"
            echo "  off    - turn off k8s bash prompt"
            echo "  events - show k8s events"
            return 1
        ;;
    esac

}

__kube_complete() {

    local __VAR
    local CURRENT="${COMP_WORDS[COMP_CWORD]}"

    COMPREPLY=()

    if [ "$COMP_CWORD" -lt 2 ]; then
        # Disable: Prefer mapfile or read -a to split command output (or quote to avoid splitting). [SC2207]
        # shellcheck disable=SC2207
        COMPREPLY=($(compgen -W "on off context config ns events set-default-config" -- "$CURRENT"))
        return
    fi

    case "${COMP_WORDS[1]}" in
        config)
            compopt -o filenames
            local FULL_PATH REL_PATH
            while IFS= read -r FULL_PATH; do
                REL_PATH="${FULL_PATH#"$_KUBECONFIG_BASE"/}"
                if [ -d "$FULL_PATH" ]; then
                    # Directories are shown only to allow traversal.
                    COMPREPLY+=("${REL_PATH}/")
                else
                    # Only regular files/symlinks are valid final completions.
                    COMPREPLY+=("${REL_PATH}")
                fi
            done < <(compgen -f -- "$_KUBECONFIG_BASE/$CURRENT")

            # If the only match is a directory, do not append a space after completion.
            if [ "${#COMPREPLY[@]}" -eq 1 ] && [ "${COMPREPLY[0]%/}" != "${COMPREPLY[0]}" ]; then
                compopt -o nospace
            fi
        ;;
        context)
            if ! __VAR="$(kubectl config get-contexts --output=name 2>&1)"; then
                echo
                cprintf -n '~r~ERROR~K~: ~d~%s' "$__VAR"
                COMPREPLY=('~=~=~=~=~=~' '=~=~=~=~=~=')
            else
                # Disable: Prefer mapfile or read -a to split command output (or quote to avoid splitting). [SC2207]
                # shellcheck disable=SC2207
                COMPREPLY=($(compgen -W "$__VAR" -- "$CURRENT"))
            fi
        ;;
        ns)
            if ! __VAR="$(kubectl get namespace -o jsonpath='{.items[*].metadata.name}' 2>&1)"; then
                echo
                cprintf -n '~r~ERROR~K~: ~d~%s' "$__VAR"
                COMPREPLY=('~=~=~=~=~=~' '=~=~=~=~=~=')
            else
                # Disable: Prefer mapfile or read -a to split command output (or quote to avoid splitting). [SC2207]
                # shellcheck disable=SC2207
                COMPREPLY=($(compgen -W "$__VAR" -- "$CURRENT"))
            fi
        ;;
    esac

}

complete -F __kube_complete ,kube

# Full support for bash completion is not available when loading shell.rc
# functions. Thus, the __start_kubectl function, which is usual to complete
# the kubectl command, is not available. Thus, we can not use it here to complete
# the alias 'k'. As a workaround, we will use wrapper function and call
# __start_kubectl if it is available.
__wrapper_start_kubectl() {
    if type -t __start_kubectl >/dev/null 2>&1; then
        __start_kubectl
    else
        # fallback: file completion as default behavior
        # Disable: Prefer mapfile or read -a to split command output (or quote to avoid splitting). [SC2207]
        # shellcheck disable=SC2207
        COMPREPLY=( $(compgen -f -- "${COMP_WORDS[COMP_CWORD]}") )
    fi
}

if [ "$(type -t compopt)" = "builtin" ]; then
    complete -o default -F __wrapper_start_kubectl k
else
    complete -o default -o nospace -F __wrapper_start_kubectl k
fi
