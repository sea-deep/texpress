#!/usr/bin/env bash
#
# texpress — lightweight Arch LaTeX toolchain installer
#
#   tectonic (Rust, on-demand packages — no TeX Live tree)
#   standalone latexmk/texcount from CTAN (Arch has no small package for these;
#   the only official path is texlive-binextra -> texlive-basic, ~1 GB+)
#   VS Code + LaTeX Workshop configured to build with tectonic
#
# Idempotent: safe to run repeatedly. Every step skips if already done.
#
# Usage:
#   ./setup.sh                 # prefer pacman (needs sudo), fall back to a rootless binary
#   ./setup.sh --rootless      # never use pacman; install tectonic binary into ~/.local/bin
#   ./setup.sh --skip-vscode   # do not touch VS Code settings
#
set -euo pipefail

PREFIX="${PREFIX:-$HOME/.local}"
BINDIR="$PREFIX/bin"
CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
LATEXMK_URL="https://mirrors.ctan.org/support/latexmk/latexmk.pl"
TEXCOUNT_URL="https://mirrors.ctan.org/support/texcount/texcount.pl"
VSCODE_SETTINGS="$HOME/.config/Code/User/settings.json"
ROOTLESS=0
DO_VSCODE=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rootless) ROOTLESS=1 ;;
    --skip-vscode) DO_VSCODE=0 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

info()  { printf '\033[1;34m[tpress]\033[0m %s\n' "$*"; }
ok()    { printf '\033[1;32m  ok:\033[0m %s\n' "$*"; }
skip()  { printf '\033[1;33m  skip:\033[0m %s\n' "$*"; }
die()   { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

download() { # url, dest
  curl -fsSL --retry 3 "$1" -o "$2" || die "failed to download $1"
}

install_tectonic() {
  if have tectonic; then
    skip "tectonic already installed at $(command -v tectonic)"
    return
  fi
  if (( ROOTLESS == 0 )) && have sudo && sudo -n true 2>/dev/null && have pacman; then
    info "installing tectonic via pacman"
    sudo pacman -S --noconfirm --needed tectonic
  else
    info "installing tectonic binary into $BINDIR (rootless)"
    mkdir -p "$BINDIR"
    local tag url
    tag="$(curl -fsSL https://api.github.com/repos/tectonic-typesetting/tectonic/releases/latest | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)"
    url="https://github.com/tectonic-typesetting/tectonic/releases/download/${tag}/tectonic-${tag#tectonic@}-x86_64-unknown-linux-gnu.tar.gz"
    local tmp
    tmp="$(mktemp -d)"
    download "$url" "$tmp/tectonic.tar.gz"
    tar xzf "$tmp/tectonic.tar.gz" -C "$tmp"
    mv "$tmp/tectonic" "$BINDIR/tectonic"
    chmod +x "$BINDIR/tectonic"
    rm -rf "$tmp"
  fi
  ok "tectonic $(tectonic --version)"
}

install_ctan_script() { # name, url
  local name="$1" url="$2"
  if have "$name"; then
    skip "$name already installed at $(command -v "$name")"
    return
  fi
  mkdir -p "$BINDIR"
  info "installing standalone $name (no TeX Live needed)"
  download "$url" "$BINDIR/$name"
  chmod +x "$BINDIR/$name"
  ok "$name installed at $BINDIR/$name"
}

write_latexmkrc() {
  local rc="$HOME/.latexmkrc"
  if [[ -f "$rc" ]] && grep -q tectonic "$rc" 2>/dev/null; then
    skip "~/.latexmkrc already configured for tectonic"
    return
  fi
  info "writing ~/.latexmkrc (pdflatex -> tectonic)"
  mkdir -p "$HOME/.config"
  printf '%s\n' '$pdf_mode = 1;' '$pdflatex = "tectonic --synctex %O %S";' >> "$rc"
  ok "appended tectonic config to ~/.latexmkrc"
}

merge_vscode_settings() {
  (( DO_VSCODE == 0 )) && { skip "VS Code setup disabled"; return; }
  command -v code >/dev/null 2>&1 || { skip "code CLI not found"; return; }
  if ! code --list-extensions 2>/dev/null | grep -q james-yu.latex-workshop; then
    info "installing LaTeX Workshop extension"
    code --install-extension james-yu.latex-workshop
  else
    skip "LaTeX Workshop extension already installed"
  fi
  [[ -f "$VSCODE_SETTINGS" ]] || { echo '{}' > "$VSCODE_SETTINGS"; }
  local patch
  patch="$(mktemp)"
  cat > "$patch" <<'JSON'
{
  "latex-workshop.latex.recipe.default": "tectonic",
  "latex-workshop.latex.autoBuild.run": "onSave",
  "latex-workshop.view.pdf.viewer": "tab",
  "latex-workshop.latex.recipes": [{ "name": "tectonic", "tools": ["tectonic"] }],
  "latex-workshop.latex.tools": [{
    "name": "tectonic",
    "command": "tectonic",
    "args": ["-X", "compile", "%DOC_EXT%", "--keep-intermediates", "--keep-logs", "--synctex"]
  }]
}
JSON
  if jq -e '."latex-workshop.latex.tools" != null' "$VSCODE_SETTINGS" >/dev/null 2>&1; then
    skip "VS Code settings already have LaTeX Workshop config"
  else
    cp "$VSCODE_SETTINGS" "$VSCODE_SETTINGS.bak.texpress"
    jq -s '.[0] + .[1]' "$VSCODE_SETTINGS" "$patch" > "$VSCODE_SETTINGS.tmp" && mv "$VSCODE_SETTINGS.tmp" "$VSCODE_SETTINGS"
    ok "merged LaTeX Workshop settings (backup: $VSCODE_SETTINGS.bak.texpress)"
  fi
  rm -f "$patch"
}

summary() {
  printf '\n\033[1;34m[tpress]\033[0m summary\n'
  printf '  tectonic    : %s\n' "$(command -v tectonic || echo MISSING)"
  printf '  latexmk     : %s\n' "$(command -v latexmk || echo MISSING)"
  printf '  texcount    : %s\n' "$(command -v texcount || echo MISSING)"
  printf '  binary size : %s\n' "$(du -sh "$BINDIR/tectonic" 2>/dev/null | cut -f1)"
  printf '  bundle cache: %s\n' "$(du -sh "$CACHE_HOME/tectonic" 2>/dev/null | cut -f1 || echo 'not warmed yet (first compile downloads it)')"
}

install_tectonic
install_ctan_script latexmk "$LATEXMK_URL"
install_ctan_script texcount "$TEXCOUNT_URL"
write_latexmkrc
merge_vscode_settings
summary
printf '\nTip: open a folder in VS Code, press Ctrl+Alt+B to build. First compile downloads the TeX bundle.\n'
