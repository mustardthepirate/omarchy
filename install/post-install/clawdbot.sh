# Install Clawdbot local tooling (CLI only). Configuration happens later.

set -euo pipefail

echo "Installing Clawdbot CLI (local tooling)..."

if command -v clawdbot >/dev/null 2>&1; then
  echo "clawdbot already installed"
  exit 0
fi

# Ensure mise exists (Omarchy uses mise for tooling)
if ! command -v mise >/dev/null 2>&1; then
  echo "[omarchy] mise not found; skipping clawdbot install"
  exit 0
fi

# Ensure a recent node is available. Use the version Omarchy itself uses.
NODE_VERSION="${OMARCHY_NODE_VERSION:-25.4.0}"

# Install node via mise.
mise install "node@${NODE_VERSION}" >/dev/null

# Install clawdbot globally into ~/.local so it doesn't require sudo.
export NPM_CONFIG_PREFIX="$HOME/.local"
mkdir -p "$HOME/.local/bin"

# Use mise exec so PATH is correct in non-interactive shells.
mise exec "node@${NODE_VERSION}" -- npm install -g clawdbot

if command -v clawdbot >/dev/null 2>&1; then
  echo "clawdbot installed: $(clawdbot --version 2>/dev/null || echo ok)"
else
  echo "[omarchy] clawdbot install finished but binary not on PATH"
  echo "[omarchy] Try: export PATH=\"$HOME/.local/bin:$PATH\""
fi
