#!/bin/bash
# configure_docker_daemon.sh
# Adds log-driver/log-opts and disables IPv6 in /etc/docker/daemon.json
# Safe: each section is skipped independently if already configured
# Requires: jq

set -euo pipefail

DAEMON_JSON="./daemon.json"

LOG_DRIVER="json-file"
LOG_MAX_SIZE="10m"
LOG_MAX_FILE="3"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

check_deps() {
    if ! command -v jq &>/dev/null; then
        echo "Error: jq is required but not installed." >&2
        echo "  Install with: apt install jq  or  yum install jq" >&2
        exit 1
    fi
}

check_json() {
    jq empty "$DAEMON_JSON" 2>/dev/null
}

has_logging_config() {
    # True if any of log-driver, log-opts, log-level exist
    jq -e '
      has("log-driver") or has("log-opts") or has("log-level")
    ' "$DAEMON_JSON" &>/dev/null
}

has_ipv6_config() {
    # True if any of ipv6, fixed-cidr-v6, ip6tables exist
    jq -e '
      has("ipv6") or has("fixed-cidr-v6") or has("ip6tables")
    ' "$DAEMON_JSON" &>/dev/null
}

merge_logging_config() {
    local tmp
    tmp=$(mktemp)
    jq \
      --arg driver   "$LOG_DRIVER" \
      --arg maxsize  "$LOG_MAX_SIZE" \
      --arg maxfile  "$LOG_MAX_FILE" \
      '.["log-driver"] = $driver |
       .["log-opts"]   = {"max-size": $maxsize, "max-file": $maxfile}' \
      "$DAEMON_JSON" > "$tmp"
    mv "$tmp" "$DAEMON_JSON"
}

merge_ipv6_disable() {
    local tmp
    tmp=$(mktemp)
    jq '
      .ipv6 = false |
      del(.["fixed-cidr-v6"]) |
      del(.["ip6tables"])
    ' "$DAEMON_JSON" > "$tmp"
    mv "$tmp" "$DAEMON_JSON"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if [[ $EUID -ne 0 ]]; then
    echo "Error: must be run as root (use sudo)" >&2
    exit 1
fi

check_deps

mkdir -p "$(dirname "$DAEMON_JSON")"

if [[ ! -f "$DAEMON_JSON" ]]; then
    echo "daemon.json not found — creating new file."
    echo "{}" > "$DAEMON_JSON"
fi

if ! check_json; then
    echo "Error: $DAEMON_JSON is not valid JSON. Fix it manually first." >&2
    exit 1
fi

# Determine what needs doing before touching anything
NEED_LOGGING=false
NEED_IPV6=false

if has_logging_config; then
    echo "Logging: already configured — skipping."
else
    NEED_LOGGING=true
fi

if has_ipv6_config; then
    echo "IPv6: already configured — skipping."
else
    NEED_IPV6=true
fi

if [[ "$NEED_LOGGING" == false && "$NEED_IPV6" == false ]]; then
    echo "Nothing to do — daemon.json already has all settings."
    exit 0
fi

# Back up once before any writes
BACKUP="${DAEMON_JSON}.bak.$(date +%Y%m%d%H%M%S)"
cp "$DAEMON_JSON" "$BACKUP"
echo "Backup saved to $BACKUP"

if [[ "$NEED_LOGGING" == true ]]; then
    merge_logging_config
    echo "Logging: added (driver=$LOG_DRIVER, max-size=$LOG_MAX_SIZE, max-file=$LOG_MAX_FILE)."
fi

if [[ "$NEED_IPV6" == true ]]; then
    merge_ipv6_disable
    echo "IPv6: disabled."
fi

echo ""
echo "Updated $DAEMON_JSON:"
cat "$DAEMON_JSON"

# Optionally reload Docker if it's running
if systemctl is-active --quiet docker; then
    read -rp $'\nReload Docker daemon now? [y/N] ' answer
    if [[ "${answer,,}" == "y" ]]; then
 #       systemctl reload docker 2>/dev/null || systemctl restart docker
        echo "Docker daemon reloaded."
    else
        echo "Skipped — run 'sudo systemctl restart docker' to apply changes."
    fi
else
    echo "Docker is not running — changes will take effect on next start."
fi
