#!/usr/bin/env bash
set -euo pipefail

repo_url="${SIMPLEOPENVPN_REPO_URL:-https://github.com/kanpianer/EasyOpenVPN.git}"

omarchy plugin add "$repo_url" --enable --yes

echo "EasyOpenVPN installed."
echo "Optional: run sudo ./setup-passwordless.sh to connect without a password prompt."
