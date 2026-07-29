#!/bin/bash

_has_function "k9s" || return 0

_absname -v __K9S_FUNCTION_FILE -- "${BASH_SOURCE[0]}"

k9s() {
    _maybe_local "k9s"
    local K9S_CONFIG_DIR="$IAM_HOME/config/k9s"
    [ -z "$__K9S_FUNCTION_FILE" ] || {
        _ensure_config "$K9S_CONFIG_DIR" "$__K9S_FUNCTION_FILE"
        unset __K9S_FUNCTION_FILE
    }
    env K9S_CONFIG_DIR="$K9S_CONFIG_DIR" k9s "$@"
}

return 0

# shellcheck disable=all
{

---- config.yaml
k9s:
  liveViewAutoRefresh: true
  refreshRate: 2
  apiServerTimeout: 15s
  maxConnRetry: 5
  readOnly: false
  noExitOnCtrlC: false
  portForwardAddress: localhost
  ui:
    enableMouse: false
    headless: false
    logoless: true
    crumbsless: false
    splashless: false
    reactive: true
    noIcons: false
    defaultsToFullScreen: false
    useFullGVRTitle: false
  skipLatestRevCheck: true
  disablePodCounting: false
  shellPod:
    image: busybox:1.35.0
    namespace: default
    limits:
      cpu: 100m
      memory: 100Mi
  imageScans:
    enable: false
    exclusions:
      namespaces: []
      labels: {}
  logger:
    tail: 100
    buffer: 5000
    sinceSeconds: -1
    textWrap: false
    disableAutoscroll: false
    showTime: false
  thresholds:
    cpu:
      critical: 90
      warn: 70
    memory:
      critical: 90
      warn: 70
  defaultView: ""

---- plugins.yaml
plugins:
  lnav_pods:
    shortCut: Ctrl-L
    description: lnav logs (current)
    scopes:
    - po
    command: lnav
    background: false
    args:
    - -e
    - "kubectl logs $NAME -n $NAMESPACE --all-containers --max-log-requests 10 --context $CONTEXT -f --since 5m"
  lnav_pods_all:
    shortCut: Shift-L
    description: lnav logs (all)
    scopes:
    - po
    command: lnav
    background: false
    args:
    - -e
    - "kubectl logs $NAME -n $NAMESPACE --all-containers --max-log-requests 10 --context $CONTEXT -f"
  lnav_containers:
    shortCut: Ctrl-L
    description: lnav logs (current)
    scopes:
    - containers
    command: lnav
    background: false
    args:
    - -e
    - "kubectl logs $POD -c $NAME -n $NAMESPACE --context $CONTEXT -f --since 5m"
  lnav_containers_all:
    shortCut: Shift-L
    description: lnav logs (all)
    scopes:
    - containers
    command: lnav
    background: false
    args:
    - -e
    - "kubectl logs $POD -c $NAME -n $NAMESPACE --context $CONTEXT -f"
  debug-ephemeral:
    shortCut: Shift-D
    confirm: false
    description: "Debug (Ephemeral)"
    scopes:
      - pods
      - containers
    command: sh
    background: false
    args:
      - -c
      - sh "$K9S_CONFIG_DIR"/k9s-debug.sh "$CONTEXT" "$NAMESPACE" "$POD" "$NAME" "$CONTAINER"

---- k9s-debug.sh
#!/bin/sh
# Map cluster contexts to their respective private debug images

KUBE_CONTEXT="$1"
POD_NAMESPACE="$2"
POD_NAME="$3"

if [ -z "$POD_NAME" ]; then
    POD_NAME="$4"
    TARGET_CONTAINER=''
else
    TARGET_CONTAINER="$4"
fi

SPARK_FAB_DEBUG_IMAGE="spark-fab/tools-debug-image:main-260715.0"

# Exit if pod name is missing
if [ -z "$POD_NAME" ]; then
    echo "Error: Pod name is required."
    sleep 2
    exit 1
fi

# Define private registry mappings based on kubeconfig context
case "$KUBE_CONTEXT" in
    spark-fab-*-nbprod)
        DEBUG_IMAGE="ecr.techdev.ormcodigital.com/$SPARK_FAB_DEBUG_IMAGE"
        ;;
    sparkfab-*-eks|eks/sparkfab-*-eks)
        DEBUG_IMAGE="448049824165.dkr.ecr.us-east-1.amazonaws.com/$SPARK_FAB_DEBUG_IMAGE"
        ;;
    *)
        DEBUG_IMAGE="docker.io/nicolaka/netshoot:latest" # Default fallback
        ;;
esac

echo "Starting ephemeral debug session in context: $KUBE_CONTEXT"
echo "Image: $DEBUG_IMAGE"
echo
echo "Pod      : $POD_NAME"
echo "Namespace: $POD_NAMESPACE"
echo "Container: $TARGET_CONTAINER"
echo

set -- kubectl --context "$KUBE_CONTEXT" \
    --namespace "$POD_NAMESPACE" \
    debug -it "$POD_NAME" \
    --image="$DEBUG_IMAGE" \
    --profile=sysadmin \
    --env="TERM=${TERM:-xterm}" \
    --share-processes

# Execute kubectl debug with ephemeral container
# If a specific container is selected, share its process namespace
if [ -n "$TARGET_CONTAINER" ]; then
    set -- "$@" --target="$TARGET_CONTAINER"
fi

SHELL_DISCOVERY_CMD="[ -x /bin/bash ] && exec /bin/bash || [ -x /usr/bin/bash ] && exec /usr/bin/bash || exec /bin/sh"

set -- "$@" -- sh -c "$SHELL_DISCOVERY_CMD"

if ! "$@"; then
    echo
    echo "ERROR: something was wrong!"
    sleep 5
    exit 1
fi
----
}
