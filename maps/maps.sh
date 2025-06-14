#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COASTLINE_DIR="${SCRIPT_DIR}/coastline"
LANDCOVER_DIR="${SCRIPT_DIR}/landcover"
ELEVATION_DIR="${SCRIPT_DIR}/elevation"
ELEVATION_CACHE_DIR="${ELEVATION_DIR}/cache"
ELEVATION_REGION_DIR="${ELEVATION_DIR}/region"
CONTOUR_BASE="${ELEVATION_DIR}/contours_current"

BASE_URL="https://download.geofabrik.de/europe"
CONFIG="${TILEMAKER_CONFIG:-${SCRIPT_DIR}/config-openmaptiles.json}"
PROCESS="${TILEMAKER_PROCESS:-${SCRIPT_DIR}/process-openmaptiles.lua}"

COASTLINE_SHAPE="${SCRIPT_DIR}/coastline/water_polygons.shp"
URBAN_SHAPE="${SCRIPT_DIR}/landcover/ne_10m_urban_areas/ne_10m_urban_areas.shp"
ICE_SHAPE="${SCRIPT_DIR}/landcover/ne_10m_antarctic_ice_shelves_polys/ne_10m_antarctic_ice_shelves_polys.shp"
GLACIER_SHAPE="${SCRIPT_DIR}/landcover/ne_10m_glaciated_areas/ne_10m_glaciated_areas.shp"

WATER_POLYGONS_URL="https://osmdata.openstreetmap.de/download/water-polygons-split-4326.zip"
NATURAL_EARTH_BASE_URL="https://naciscdn.org/naturalearth/10m"

# SRTM produkt dla elevation/eio:
# SRTM1 (30m) domyślnie, SRTM3 (90m) lżejszy.
EIO_PRODUCT="${EIO_PRODUCT:-SRTM1}"
EIO_CACHE="${ELEVATION_CACHE_DIR}/eio"
EIO_SPLIT_MAX_DEPTH="${EIO_SPLIT_MAX_DEPTH:-6}"

log(){ printf '%s\n' "$*" >&2; }
die(){ log "ERROR: $*"; exit 1; }

CURL_OPTS=(
  -L --fail
  --retry 5
  --retry-all-errors
  --connect-timeout 15
  --continue-at -
  --silent --show-error
)

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing dependency: $1"
}

download_zip() {
  local url="$1" dest_dir="$2" label="$3"
  mkdir -p "$dest_dir"
  local zip_path="${dest_dir}/$(basename "$url")"
  local part_path="${zip_path}.part"

  log "Downloading ${label} from ${url}"
  curl "${CURL_OPTS[@]}" --output "$part_path" "$url"
  mv -f "$part_path" "$zip_path"

  log "Extracting ${label}..."
  unzip -oq "$zip_path" -d "$dest_dir"
  rm -f "$zip_path"
}

fetch_water_polygons() {
  local target="${COASTLINE_DIR}/water_polygons.shp"
  if [ -f "$target" ]; then
    log "Water polygons already present: $target"
    return
  fi

  log "Fetching water polygons (~880MB download)..."
  download_zip "$WATER_POLYGONS_URL" "$COASTLINE_DIR" "water polygons"

  local shp
  shp="$(find "$COASTLINE_DIR" -maxdepth 3 -type f -name "*water*polygon*.shp" | head -n 1)"
  [ -n "$shp" ] || die "Unable to locate water polygons shapefile after download"

  local base="${shp%.*}"
  local dest_base="${COASTLINE_DIR}/water_polygons"
  for ext in shp shx dbf prj cpg qix; do
    [ -f "${base}.${ext}" ] && cp "${base}.${ext}" "${dest_base}.${ext}"
  done
  log "Normalised water polygons to ${dest_base}.shp"
}

fetch_natural_earth_dataset() {
  local archive_path="$1" dest_dir="$2" shp_basename="$3" label="$4"
  local target="${dest_dir}/${shp_basename}.shp"
  if [ -f "$target" ]; then
    log "${label} already present: $target"
    return
  fi
  download_zip "${NATURAL_EARTH_BASE_URL}/${archive_path}" "$dest_dir" "$label"
  [ -f "$target" ] || die "Expected shapefile missing after download: $target"
}

ensure_requirements() {
  [ -f "$CONFIG" ] || die "Missing tilemaker config: $CONFIG"
  [ -f "$PROCESS" ] || die "Missing tilemaker process: $PROCESS"
}

prepare_elevation_dirs() {
  mkdir -p "$ELEVATION_CACHE_DIR" "$ELEVATION_REGION_DIR" "$EIO_CACHE"
}

parse_bbox_values() {
  local bbox="$1"
  python3 - "$bbox" <<'PY'
import sys
bbox = sys.argv[1].strip()
if not bbox.startswith('(') or not bbox.endswith(')'):
    raise SystemExit(f'Invalid bbox format: {bbox}')
parts = [p.strip() for p in bbox[1:-1].split(',')]
if len(parts) != 4:
    raise SystemExit(f'Invalid bbox coordinate count: {bbox}')
print(' '.join(parts))
PY
}

detect_nodata_value() {
  local tif="$1"
  local v
  v="$(gdalinfo "$tif" | awk -F'=' '/NoData Value/ {print $NF; exit}' | tr -d ' ')"
  if [ -z "$v" ] || [ "$v" = "nan" ] || [ "$v" = "NaN" ]; then
    return 1
  fi
  printf '%s\n' "$v"
}

remove_vector_dataset() {
  local base="$1"
  rm -f "${base}.shp" "${base}.shx" "${base}.dbf" "${base}.prj" "${base}.cpg" "${base}.qix"
}

choose_split_axis_and_midpoint() {
  local min_lon="$1" min_lat="$2" max_lon="$3" max_lat="$4"
  python3 - "$min_lon" "$min_lat" "$max_lon" "$max_lat" <<'PY'
import sys

min_lon, min_lat, max_lon, max_lat = map(float, sys.argv[1:])
span_lon = max_lon - min_lon
span_lat = max_lat - min_lat
eps = 1e-9

if span_lon <= eps and span_lat <= eps:
    raise SystemExit("Unable to split bbox: zero-sized extent")

if span_lon >= span_lat and span_lon > eps:
    axis = "lon"
    mid = (min_lon + max_lon) / 2.0
else:
    axis = "lat"
    mid = (min_lat + max_lat) / 2.0

print(f"{axis} {mid:.10f}")
PY
}

clip_dem_bbox_recursive() {
  local out_tif="$1"
  local min_lon="$2" min_lat="$3" max_lon="$4" max_lat="$5"
  local depth="$6" node="$7" region="$8" work_dir="$9"
  local err_log="${work_dir}/${region}_${node}.eio.log"

  rm -f "$out_tif"
  if eio --product "$EIO_PRODUCT" --cache_dir "$EIO_CACHE" \
    clip -o "$out_tif" --bounds "$min_lon" "$min_lat" "$max_lon" "$max_lat" \
    2>"$err_log"; then
    [ -s "$out_tif" ] || die "DEM clip produced empty output for ${region}: $out_tif"
    rm -f "$err_log"
    return 0
  fi

  if ! grep -q "Too many tiles" "$err_log"; then
    cat "$err_log" >&2
    die "eio clip failed for ${region} bbox=${min_lon},${min_lat},${max_lon},${max_lat}"
  fi

  if [ "$depth" -ge "$EIO_SPLIT_MAX_DEPTH" ]; then
    cat "$err_log" >&2
    die "Exceeded EIO split depth (${EIO_SPLIT_MAX_DEPTH}) for ${region}"
  fi

  local axis mid
  read -r axis mid <<<"$(choose_split_axis_and_midpoint "$min_lon" "$min_lat" "$max_lon" "$max_lat")"
  log "eio tile limit reached for ${region}; splitting ${axis} at ${mid} (depth ${depth})"

  local left_tif="${work_dir}/${region}_${node}a.tif"
  local right_tif="${work_dir}/${region}_${node}b.tif"
  local vrt_file="${work_dir}/${region}_${node}.vrt"

  if [ "$axis" = "lon" ]; then
    clip_dem_bbox_recursive "$left_tif" "$min_lon" "$min_lat" "$mid" "$max_lat" "$((depth + 1))" "${node}a" "$region" "$work_dir"
    clip_dem_bbox_recursive "$right_tif" "$mid" "$min_lat" "$max_lon" "$max_lat" "$((depth + 1))" "${node}b" "$region" "$work_dir"
  else
    clip_dem_bbox_recursive "$left_tif" "$min_lon" "$min_lat" "$max_lon" "$mid" "$((depth + 1))" "${node}a" "$region" "$work_dir"
    clip_dem_bbox_recursive "$right_tif" "$min_lon" "$mid" "$max_lon" "$max_lat" "$((depth + 1))" "${node}b" "$region" "$work_dir"
  fi

  gdalbuildvrt -q "$vrt_file" "$left_tif" "$right_tif"
  gdal_translate -q -of GTiff "$vrt_file" "$out_tif"
  rm -f "$left_tif" "$right_tif" "$vrt_file" "$err_log"
}

build_contours() {
  local pbf="$1" region="$2"

  [ -f "$pbf" ] || die "Missing OSM extract for contour generation: $pbf"

  local bbox
  bbox="$(osmium fileinfo -e -g header.boxes "$pbf" | head -n 1)"
  [ -n "$bbox" ] || die "Unable to read bbox from $pbf"

  local min_lon min_lat max_lon max_lat
  read -r min_lon min_lat max_lon max_lat <<<"$(parse_bbox_values "$bbox")"

  local region_dem="${ELEVATION_REGION_DIR}/${region}_dem.tif"
  local region_contour_gpkg="${ELEVATION_REGION_DIR}/${region}_contour.gpkg"

  rm -f "$region_dem" "$region_contour_gpkg"

  local dem_work_dir
  dem_work_dir="$(mktemp -d "${ELEVATION_REGION_DIR}/${region}_dem_work_XXXXXX")"

  log "Clipping DEM via elevation/eio (${EIO_PRODUCT}) for ${region} bbox=${min_lon},${min_lat},${max_lon},${max_lat}"
  clip_dem_bbox_recursive "$region_dem" "$min_lon" "$min_lat" "$max_lon" "$max_lat" 0 "root" "$region" "$dem_work_dir"
  rm -rf "$dem_work_dir"

  [ -s "$region_dem" ] || die "DEM clip failed / empty output: $region_dem"

  local snodata_arg=()
  if nodata="$(detect_nodata_value "$region_dem")"; then
    snodata_arg=(-snodata "$nodata")
  fi

  gdal_contour -i 20 -a ele "${snodata_arg[@]}" -f GPKG -nln contour "$region_dem" "$region_contour_gpkg"

  remove_vector_dataset "$CONTOUR_BASE"
  ogr2ogr -overwrite -f "ESRI Shapefile" "${CONTOUR_BASE}.shp" \
    "$region_contour_gpkg" contour \
    -dialect SQLite \
    -sql "SELECT *, CASE WHEN CAST(ele AS INTEGER) % 100 = 0 THEN 1 ELSE 0 END AS cidx, CASE WHEN CAST(ele AS INTEGER) % 100 = 0 THEN 1 ELSE 0 END AS level FROM contour"
}

validate_contour_layer_in_mbtiles() {
  local mbtiles="$1"
  local metadata_json
  metadata_json="$(sqlite3 "$mbtiles" "SELECT value FROM metadata WHERE name='json';")"
  [ -n "$metadata_json" ] || die "Missing metadata json in $mbtiles"

  printf '%s' "$metadata_json" | grep -q '"id":"contour"'   || die "Contour layer not present in metadata json for $mbtiles"
  printf '%s' "$metadata_json" | grep -q '"ele":"Number"'   || die "Contour ele field missing in metadata json for $mbtiles"
  printf '%s' "$metadata_json" | grep -q '"cidx":"Number"'  || die "Contour cidx field missing in metadata json for $mbtiles"
  printf '%s' "$metadata_json" | grep -q '"level":"Number"' || die "Contour level field missing in metadata json for $mbtiles"
}

require_cmd tilemaker
require_cmd wget
require_cmd curl
require_cmd unzip
require_cmd gunzip
require_cmd python3
require_cmd osmium
require_cmd sqlite3
require_cmd ogr2ogr
require_cmd gdal_contour
require_cmd gdalinfo
require_cmd gdalbuildvrt
require_cmd gdal_translate
require_cmd eio

cd "$SCRIPT_DIR"
ensure_requirements
prepare_elevation_dirs

fetch_water_polygons
fetch_natural_earth_dataset "cultural/ne_10m_urban_areas.zip"                                    "${LANDCOVER_DIR}/ne_10m_urban_areas"                    "ne_10m_urban_areas"                    "Natural Earth urban areas"
fetch_natural_earth_dataset "physical/ne_10m_antarctic_ice_shelves_polys.zip"                     "${LANDCOVER_DIR}/ne_10m_antarctic_ice_shelves_polys"    "ne_10m_antarctic_ice_shelves_polys"    "Natural Earth antarctic ice shelves"
fetch_natural_earth_dataset "physical/ne_10m_glaciated_areas.zip"                                 "${LANDCOVER_DIR}/ne_10m_glaciated_areas"                "ne_10m_glaciated_areas"                "Natural Earth glaciated areas"

PBF="poland-latest.osm.pbf"
MBTILES="poland.mbtiles"

wget -N "${BASE_URL}/${PBF}"
build_contours "$PBF" "poland"
tilemaker --input="${PBF}" --output="${MBTILES}" --config="${CONFIG}" --process="${PROCESS}"
validate_contour_layer_in_mbtiles "$MBTILES"

log "Done: ${SCRIPT_DIR}/${MBTILES}"
