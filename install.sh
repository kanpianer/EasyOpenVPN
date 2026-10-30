#!/usr/bin/env bash
set -euo pipefail

repo_url="${SIMPLEOPENVPN_REPO_URL:-https://github.com/kanpianer/EasyOpenVPN.git}"

echo "Installing dependencies..."
omarchy pkg add openvpn jq zenity python nftables

echo "Installing EasyOpenVPN plugin..."
omarchy plugin add "$repo_url" --enable --yes

echo "EasyOpenVPN installed."
echo "Optional: run sudo ./setup-passwordless.sh to connect without a password prompt."
