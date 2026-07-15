#!/bin/bash
# Deploy the RedFence monitoring agent on an EC2 instance.
# Copy this whole folder anywhere on the instance (e.g. via scp) and run
# this script — it installs itself into /opt/redfence-monitoring-agent,
# then starts whichever exporter(s) you choose via docker compose.
#
# Usage:
#   ./deploy.sh            interactive — prompts for which service(s)
#   ./deploy.sh ec2         EC2 host metrics only   (node-exporter, :9100)
#   ./deploy.sh docker      Docker container metrics only (cadvisor, :8080)
#   ./deploy.sh both        both exporters
set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_DIR="/opt/redfence-monitoring-agent"

command -v docker >/dev/null 2>&1 || {
    echo "ERROR: docker not found. Install Docker + the compose plugin first," >&2
    echo "       e.g. https://docs.docker.com/engine/install/" >&2
    exit 1
}
docker compose version >/dev/null 2>&1 || {
    echo "ERROR: 'docker compose' (v2 plugin) not found." >&2
    exit 1
}

# ---------------------------------------------------------------------------
# Install into /opt/redfence-monitoring-agent. Always re-syncs compose.yaml,
# deploy.sh, and help.md from wherever this script was run from — this
# folder is meant to be deployed via this script, not hand-edited in place.
# Only escalates with sudo if the current user can't already write there
# (e.g. first run on a fresh instance where /opt is root-owned).
echo "[deploy] installing into $TARGET_DIR"
mkdir -p "$TARGET_DIR" 2>/dev/null || sudo mkdir -p "$TARGET_DIR"
[ -w "$TARGET_DIR" ] || sudo chown -R "$(id -u):$(id -g)" "$TARGET_DIR"

if [ "$SOURCE_DIR" != "$TARGET_DIR" ]; then
    cp "$SOURCE_DIR/compose.yaml" "$TARGET_DIR/"
    cp "$SOURCE_DIR/deploy.sh" "$TARGET_DIR/"
    [ -f "$SOURCE_DIR/help.md" ] && cp "$SOURCE_DIR/help.md" "$TARGET_DIR/"
fi

cd "$TARGET_DIR"

# ---------------------------------------------------------------------------
CHOICE="${1:-}"
if [ -z "$CHOICE" ]; then
    echo "RedFence Monitoring Agent — what do you want to monitor on this instance?"
    echo "  1) EC2 host metrics only         (node-exporter, port 9100)"
    echo "  2) Docker container metrics only (cadvisor, port 8080)"
    echo "  3) Both"
    read -rp "Select [1-3]: " ans
    case "$ans" in
        1) CHOICE="ec2" ;;
        2) CHOICE="docker" ;;
        3) CHOICE="both" ;;
        *) echo "ERROR: invalid selection" >&2; exit 1 ;;
    esac
fi

case "$CHOICE" in
    ec2)    SERVICES="node-exporter" ;;
    docker) SERVICES="cadvisor" ;;
    both)   SERVICES="node-exporter cadvisor" ;;
    *)      echo "ERROR: unknown argument '$CHOICE' (expected ec2|docker|both)" >&2; exit 1 ;;
esac

echo "[deploy] starting: $SERVICES"
# shellcheck disable=SC2086
docker compose up -d $SERVICES

echo ""
echo "Done. Status:"
docker compose ps

echo ""
echo "Installed at: $TARGET_DIR"
echo "Next: open the listed port(s) to the monitoring server's security group"
echo "only, then add this instance's private IP as a Prometheus target on the"
echo "monitoring server — see help.md in this folder."
