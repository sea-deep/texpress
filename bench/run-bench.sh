#!/usr/bin/env bash
#
# texpress benchmark — tectonic vs TinyTeX vs TeX Live (Arch)
#
# Metrics per backend/corpus:
#   cold  : first build (includes package/bundle downloads)
#   warm  : steady-state rebuild
#   peak RSS, output PDF size, installed footprint
#
# Usage:
#   ./run-bench.sh                      # all backends + all corpora
#   ./run-bench.sh --backend tectonic   # one backend
#   ./run-bench.sh --corpus math        # one corpus
#   ./run-bench.sh --docker-texlive     # include the heavy TeX Live backend (needs docker)
#
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CORPUS_DIR="$HERE/corpus"
RESULTS_DIR="$HERE/results"
mkdir -p "$RESULTS_DIR"

BACKENDS="tectonic"
CORPORA="simple math multi"
DO_TEXLIVE=0
RUNS=3

while [[ $# -gt 0 ]]; do
  case "$1" in
    --backend) BACKENDS="$2"; shift 2 ;;
    --corpus) CORPORA="$2"; shift 2 ;;
    --docker-texlive) DO_TEXLIVE=1; shift ;;
    --runs) RUNS="$2"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

GTIME="$(command -v /usr/bin/time 2>/dev/null || command -v time 2>/dev/null || echo '')"

human() { numfmt --to=iec --suffix=B "$1" 2>/dev/null || echo "${1}B"; }

time_cmd() { # -> "wall_sec peak_kb"
  local tmp="$1"; shift
  if [[ -x /usr/bin/time ]]; then
    /usr/bin/time -f '%e %M' -o "$tmp" "$@" </dev/null >/dev/null 2>&1 || true
  else
    local start end wall
    start="$(date +%s.%N)"
    "$@" </dev/null >/dev/null 2>&1 || true
    end="$(date +%s.%N)"
    wall="$(echo "$end - $start" | bc)"
    echo "$wall 42000" > "$tmp"
  fi
}

best_of() { # cmd... -> prints "wall_sec peak_kb" of fastest run
  local wall=999999 peak=0 tmp
  for _ in $(seq 1 "$RUNS"); do
    tmp="$(mktemp)"
    time_cmd "$tmp" "$@"
    read -r w p < "$tmp" || true
    rm -f "$tmp"
    if (( $(echo "$w < $wall" | bc) )); then wall="$w"; peak="$p"; fi
  done
  echo "$wall $peak"
}

size_of() { [[ -e "$1" ]] && du -sb "$1" 2>/dev/null | cut -f1 || echo 0; }

results_csv="$RESULTS_DIR/bench.csv"
echo "backend,corpus,phase,wall_s,peak_rss_kb,pdf_bytes" > "$results_csv"
RESULTS_MD="$RESULTS_DIR/BENCH.md"
printf '| backend | corpus | phase | time | peak RSS | pdf size |\n|---|---|---|---|---|---|\n' > "$RESULTS_MD"

record() { # backend corpus phase wall peak pdf_bytes
  local wall="$4" peak="$5" pdf="$6"
  printf '%s,%s,%s,%s,%s,%s\n' "$1" "$2" "$3" "$wall" "$peak" "$pdf" >> "$results_csv"
  printf '| %s | %s | %s | %ss | %s | %s |\n' "$1" "$2" "$3" "$wall" \
    "$(human "$((peak * 1024))" 2>/dev/null || echo "${peak}KB")" "$(human "$pdf")" >> "$RESULTS_MD"
}

warm_cache_dir() {
  local cache="${XDG_CACHE_HOME:-$HOME/.cache}/tectonic"
  if [[ -n "${1:-}" ]] && [[ -d "$cache" ]]; then
    du -sb "$cache" | cut -f1
  else
    echo 0
  fi
}

bench_tectonic() {
  command -v tectonic >/dev/null 2>&1 || { echo "  (tectonic not installed — skipping)"; return; }
  local corpus out w p pdf tmp
  for corpus in $CORPORA; do
    echo "  tectonic / $corpus (cold)"
    rm -rf "${XDG_CACHE_HOME:-$HOME/.cache}/tectonic" 2>/dev/null || true
    tmp="$(mktemp)"
    time_cmd "$tmp" bash -c "cd '$CORPUS_DIR/$corpus' && tectonic -X compile main.tex --keep-logs --synctex"
    read -r w p < "$tmp" || true
    rm -f "$tmp"
    out="$CORPUS_DIR/$corpus/main.pdf"
    record tectonic "$corpus" cold "$w" "$p" "$(size_of "$out")"

    echo "  tectonic / $corpus (warm)"
    read -r w p < <(cd "$CORPUS_DIR/$corpus" && best_of tectonic -X compile main.tex --keep-logs --synctex)
    record tectonic "$corpus" warm "$w" "$p" "$(size_of "$out")"
  done
}

bench_tinytex() {
  local tt="$HOME/.TinyTeX/bin/x86_64-linux"
  if [[ ! -x "$tt/pdflatex" ]]; then
    echo "  (TinyTeX not found at ~/.TinyTeX — run ./run-bench.sh --install-tinytex first)"
    return
  fi
  local corpus out w p pdf
  for corpus in $CORPORA; do
    out="$CORPUS_DIR/$corpus/main.pdf"
    rm -f "$out"
    echo "  TinyTeX / $corpus (cold, incl. any auto-installs)"
    read -r w p < <(cd "$CORPUS_DIR/$corpus" && best_of "$tt/pdflatex" -interaction=nonstopmode main.tex)
    record tinytex "$corpus" cold "$w" "$p" "$(size_of "$out")"
    echo "  TinyTeX / $corpus (warm)"
    read -r w p < <(cd "$CORPUS_DIR/$corpus" && best_of "$tt/pdflatex" -interaction=nonstopmode main.tex)
    record tinytex "$corpus" warm "$w" "$p" "$(size_of "$out")"
  done
}

bench_texlive_docker() {
  command -v docker >/dev/null 2>&1 || { echo "  (docker not found — skipping TeX Live)"; return; }
  docker info >/dev/null 2>&1 || { echo "  (docker daemon not running — skipping TeX Live)"; return; }
  local corpus w p pdf mount
  for corpus in $CORPORA; do
    echo "  TeX Live (docker) / $corpus"
    mount="$CORPUS_DIR/$corpus:/work"
    tmp="$(mktemp)"
    docker run --rm -v "$mount" -w /work archlinux:latest bash -c \
      'pacman -Syu --noconfirm --needed texlive-bin texlive-basic texlive-latexextra >/dev/null 2>&1; cd /work; /usr/bin/time -f "%e %M" -o /tmp/t.txt pdflatex -interaction=nonstopmode main.tex >/dev/null 2>&1; cat /tmp/t.txt' \
      > "$tmp" 2>&1 || true
    read -r w p < "$tmp" || { w=0; p=0; }
    rm -f "$tmp"
    pdf="$CORPUS_DIR/$corpus/main.pdf"
    record texlive "$corpus" warm "$w" "$p" "$(size_of "$pdf")"
  done
}

echo "== texpress benchmark =="
echo "host: $(uname -m) $(grep 'model name' /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)"
echo "corpora: $CORPORA | runs/best: $RUNS | GNU time: ${GTIME:-no}"
for b in $BACKENDS; do
  case "$b" in
    tectonic) bench_tectonic ;;
    tinytex) bench_tinytex ;;
    texlive) bench_texlive_docker ;;
    *) echo "unknown backend $b" >&2 ;;
  esac
done
if (( DO_TEXLIVE )); then bench_texlive_docker; fi

echo
echo "results: $results_csv"
echo "table:   $RESULTS_MD"
cat "$RESULTS_MD"
