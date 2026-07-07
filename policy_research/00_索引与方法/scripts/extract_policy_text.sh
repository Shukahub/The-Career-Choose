#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-policy_research}"
OUT="${2:-policy_research/06_可读文本}"
MANIFEST="$OUT/extraction_manifest.tsv"

mkdir -p "$OUT"
printf "source_path\ttext_path\tstatus\tbytes\n" > "$MANIFEST"

extract_html() {
  local src="$1"
  local dst="$2"
  perl -0777 -pe '
    s/<script\b[^>]*>.*?<\/script>//gis;
    s/<style\b[^>]*>.*?<\/style>//gis;
    s/<[^>]+>/\n/g;
    s/&nbsp;/ /g;
    s/&amp;/\&/g;
    s/&lt;/</g;
    s/&gt;/>/g;
    s/&quot;/"/g;
    s/&#39;/'"'"'/g;
    s/[ \t]+\n/\n/g;
    s/\n{3,}/\n\n/g;
  ' "$src" > "$dst"
}

extract_doc() {
  local src="$1"
  local dst="$2"
  local tmp
  tmp="$(mktemp -d)"
  libreoffice --headless --convert-to txt --outdir "$tmp" "$src" >/dev/null 2>&1
  local converted
  converted="$(find "$tmp" -maxdepth 1 -type f -name '*.txt' | head -n 1 || true)"
  if [[ -n "$converted" ]]; then
    cp "$converted" "$dst"
  else
    rm -rf "$tmp"
    return 1
  fi
  rm -rf "$tmp"
}

while IFS= read -r -d '' src; do
  rel="${src#"$ROOT"/}"
  dst="$OUT/${rel%.*}.txt"
  mkdir -p "$(dirname "$dst")"

  status="ok"
  case "${src,,}" in
    *.pdf)
      if ! pdftotext -layout "$src" "$dst" >/dev/null 2>&1; then
        status="failed"
        : > "$dst"
      fi
      ;;
    *.html|*.htm)
      if ! extract_html "$src" "$dst"; then
        status="failed"
        : > "$dst"
      fi
      ;;
    *.md|*.txt)
      cp "$src" "$dst"
      ;;
    *.doc|*.docx)
      if ! extract_doc "$src" "$dst"; then
        status="failed"
        : > "$dst"
      fi
      ;;
    *)
      status="skipped"
      : > "$dst"
      ;;
  esac

  bytes="$(wc -c < "$dst" | tr -d ' ')"
  printf "%s\t%s\t%s\t%s\n" "$src" "$dst" "$status" "$bytes" >> "$MANIFEST"
done < <(
  find "$ROOT" \
    -path "$OUT" -prune -o \
    -type f \( -name '*.pdf' -o -name '*.html' -o -name '*.htm' -o -name '*.md' -o -name '*.txt' -o -name '*.doc' -o -name '*.docx' \) \
    -print0
)

printf "Wrote %s\n" "$MANIFEST"
