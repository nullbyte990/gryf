#!/usr/bin/env sh
set -eu

BASE_URL="${BROUTER_SEGMENTS_URL:-https://brouter.de/brouter/segments4}"
TARGET_DIR="${BROUTER_SEGMENTS_DIR:-$(CDPATH= cd -- "$(dirname -- "$0")/segments4" && pwd)}"

# BRouter segments are 5x5 degree tiles. These files cover Poland and a small border buffer.
SEGMENTS="
E10_N45
E10_N50
E15_N45
E15_N50
E20_N45
E20_N50
E25_N45
E25_N50
"

mkdir -p "$TARGET_DIR"

fetch() {
  url="$1"
  output="$2"
  wget --output-document="$output" "$url"
}

echo "Downloading BRouter RD5 segments to: $TARGET_DIR"

for segment in $SEGMENTS; do
  file="${segment}.rd5"
  url="${BASE_URL}/${file}"
  output="${TARGET_DIR}/${file}"

  if [ -s "$output" ]; then
    echo "Skipping existing segment: $file"
    continue
  fi

  echo "Downloading: $file"
  fetch "$url" "$output"
done

echo "Done. Restart BRouter if it is already running: docker compose restart brouter"
