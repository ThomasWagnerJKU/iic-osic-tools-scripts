#!/bin/bash
# ========================================================================
# Installs (or updates) the iic-osic-tools scripts and config files.
#
# All files are installed owned by root, as root runs the sbin scripts.
# The local settings in /etc/iic-osic-tools/iic-osic-tools.conf are only
# created if missing, never overwritten.
#
# Usage (as root): ./install.sh [-n]
#        -n  dry run, only shows what would be done (works as any user)
#
# SPDX-FileCopyrightText: 2026 Thomas Wagner, Johannes Kepler University
# SPDX-License-Identifier: Apache-2.0
# ========================================================================

DRY_RUN=0
case "${1:-}" in
    -n|--dry-run) DRY_RUN=1 ;;
    -h|--help)    sed -n '3,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    "")           ;;
    *)            echo "[ERROR] Unknown option $1, see $0 -h."; exit 1 ;;
esac

if [ "$DRY_RUN" = 0 ] && [ "$(id -u)" != 0 ]; then
    echo "[ERROR] Please run as root (or with -n for a dry run)."
    exit 1
fi

# Install from the directory of this script, wherever it is called from
cd "$(dirname "$(readlink -f "$0")")" || exit 1

# source  destination  mode
FILES=(
    "bin/iic-osic-tools                          /usr/local/bin/iic-osic-tools                      755"
    "sbin/iic-osic-tools-enable                  /usr/local/sbin/iic-osic-tools-enable              755"
    "sbin/podman-subid-add                       /usr/local/sbin/podman-subid-add                   755"
    "sbin/iic-osic-tools-image-update            /usr/local/sbin/iic-osic-tools-image-update        755"
    "etc/containers/storage-iic-osic-tools.conf  /etc/containers/storage-iic-osic-tools.conf        644"
    "etc/profile.d/iic-osic-tools.sh             /etc/profile.d/iic-osic-tools.sh                   644"
    "etc/environment.d/50-iic-osic-tools.conf    /etc/environment.d/50-iic-osic-tools.conf          644"
)
LOCAL_CONF_SRC="etc/iic-osic-tools/iic-osic-tools.conf"
LOCAL_CONF="/etc/iic-osic-tools/iic-osic-tools.conf"

_run () {
    if [ "$DRY_RUN" = 1 ]; then
        echo "[DRY-RUN] $*"
    else
        "$@"
    fi
}

# "Installed" or, in a dry run, "Would install"
DONE="Installed"
[ "$DRY_RUN" = 1 ] && DONE="Would install"

# Check all sources first, so nothing is installed half
for entry in "${FILES[@]}" "$LOCAL_CONF_SRC - -"; do
    read -r src _ _ <<< "$entry"
    if [ ! -f "$src" ]; then
        echo "[ERROR] $src is missing, nothing installed."
        exit 1
    fi
done
for entry in "${FILES[@]}"; do
    read -r src _ _ <<< "$entry"
    case "$src" in
        bin/*|sbin/*)
            if ! bash -n "$src"; then
                echo "[ERROR] $src has a syntax error, nothing installed."
                exit 1
            fi ;;
    esac
done

RC=0
for entry in "${FILES[@]}"; do
    read -r src dst mode <<< "$entry"
    if [ -f "$dst" ] && cmp -s "$src" "$dst" && \
       [ "$(stat -c '%U:%G %a' "$dst")" = "root:root $mode" ]; then
        echo "[INFO] $dst is up to date."
        continue
    fi
    if _run install -D -o root -g root -m "$mode" "$src" "$dst"; then
        echo "[INFO] $DONE $dst."
    else
        echo "[ERROR] Could not install $dst!"
        RC=1
    fi
done

if [ -e "$LOCAL_CONF" ]; then
    echo "[INFO] $LOCAL_CONF exists, kept unchanged."
elif _run install -D -o root -g root -m 644 "$LOCAL_CONF_SRC" "$LOCAL_CONF"; then
    echo "[INFO] $DONE $LOCAL_CONF (local settings, edit as needed)."
else
    echo "[ERROR] Could not install $LOCAL_CONF!"
    RC=1
fi

# Rootless Podman ignores the image stores in /etc/containers/storage.conf,
# an older version of this setup used it
if [ -f /etc/containers/storage.conf ] && \
   grep -q 'additionalimagestores *= *\[ *"/var/local/eda/images"' /etc/containers/storage.conf; then
    echo "[HINT] /etc/containers/storage.conf still lists the shared image store, which is no longer needed there."
fi

echo
if [ "$RC" = 0 ]; then
    echo "[INFO] Done. Next steps (see README.md):"
else
    echo "[WARNING] Some files could not be installed, see above. Next steps (see README.md):"
fi
echo "       - Shared image (first time and for updates):  /usr/local/sbin/iic-osic-tools-image-update"
echo "       - Enable users:  /usr/local/sbin/iic-osic-tools-enable 'DOMAIN\\user' ..."
echo "       - Local settings (ports, firewall zone):  $LOCAL_CONF"
exit $RC
