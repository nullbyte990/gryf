#!/bin/sh
set -e

PHOTON_DATA_DIR="${PHOTON_DATA_DIR:-/photon}"
PHOTON_REGION="${PHOTON_REGION:-PL}"
PHOTON_COUNTRY_CODES="${PHOTON_COUNTRY_CODES:-PL}"
PHOTON_IMPORT_ON_START="${PHOTON_IMPORT_ON_START:-true}"
PHOTON_IMPORT_JAVA_OPTS="${PHOTON_IMPORT_JAVA_OPTS:--Xmx4G}"
PHOTON_LANGUAGES="${PHOTON_LANGUAGES:-pl,en}"
PHOTON_REQUIRE_DATA="${PHOTON_REQUIRE_DATA:-true}"
PHOTON_DUMP_URL="${PHOTON_DUMP_URL:-https://download1.graphhopper.com/public/europe/poland/photon-dump-poland-1.0-latest.jsonl.zst}"
PHOTON_IMPORT_MARKER=".gryf-import-complete"
PHOTON_MIN_DATA_SIZE_KB="${PHOTON_MIN_DATA_SIZE_KB:-102400}"

set -o pipefail 2>/dev/null || true

data_exists() {
    data_path="${PHOTON_DATA_DIR}/photon_data"

    if [ -f "${data_path}/${PHOTON_IMPORT_MARKER}" ]; then
        return 0
    fi

    if [ -d "${data_path}/node_1/data" ]; then
        data_size_kb="$(du -sk "$data_path" 2>/dev/null | awk '{print $1}')"
        [ "${data_size_kb:-0}" -ge "$PHOTON_MIN_DATA_SIZE_KB" ]
        return
    fi

    return 1
}

normalize_region() {
    case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
        pl|poland|polska)
            printf '%s' "PL"
            ;;
        *)
            return 1
            ;;
    esac
}

import_poland_dump() {
    region="$(normalize_region "$PHOTON_REGION")" || {
        echo "Unsupported PHOTON_REGION=${PHOTON_REGION}. This image is configured to import only Poland (PL)." >&2
        exit 1
    }

    if [ "$PHOTON_COUNTRY_CODES" != "PL" ]; then
        echo "Unsupported PHOTON_COUNTRY_CODES=${PHOTON_COUNTRY_CODES}. This image is configured to import only PL." >&2
        exit 1
    fi

    echo "Importing Photon data for region ${region} from ${PHOTON_DUMP_URL}."

    import_root="$(mktemp -d "${PHOTON_DATA_DIR}/.import.XXXXXX")"
    dump_file="${import_root}/photon-dump.jsonl.zst"
    chown photon:photon "$import_root"

    cleanup_import() {
        if [ -n "${import_root:-}" ] && [ -d "$import_root" ]; then
            rm -rf "$import_root"
        fi
    }
    trap cleanup_import EXIT INT TERM

    echo "Downloading Photon dump to ${dump_file}."
    curl -fL --retry 5 --retry-delay 10 --retry-connrefused -o "$dump_file" "$PHOTON_DUMP_URL"

    echo "Importing downloaded Photon dump."
    zstd --stdout -d "$dump_file" \
        | su-exec photon java ${PHOTON_IMPORT_JAVA_OPTS} -jar /opt/photon/photon.jar import \
        -import-file - \
        -country-codes "$PHOTON_COUNTRY_CODES" \
        -languages "$PHOTON_LANGUAGES" \
        -data-dir "${import_root}/data"

    if [ ! -d "${import_root}/data/photon_data/node_1/data" ]; then
        echo "Photon import finished, but expected data directory was not created." >&2
        exit 1
    fi

    touch "${import_root}/data/photon_data/${PHOTON_IMPORT_MARKER}"
    chown -R photon:photon "${import_root}/data/photon_data"

    rm -rf "${PHOTON_DATA_DIR}/photon_data"
    mv "${import_root}/data/photon_data" "${PHOTON_DATA_DIR}/photon_data"
    rmdir "${import_root}/data" 2>/dev/null || true
    rm -rf "$import_root"
    import_root=""

    echo "Photon import completed."
}

chown -R photon:photon /photon

if [ "$PHOTON_IMPORT_ON_START" = "true" ] && ! data_exists; then
    import_poland_dump
fi

if [ "$PHOTON_REQUIRE_DATA" = "true" ] && ! data_exists; then
    echo "Photon data directory is empty and automatic import did not create it." >&2
    echo "Check Photon logs, then recreate photon:" >&2
    echo "  docker compose logs photon" >&2
    echo "  docker compose up -d --force-recreate photon" >&2
    exit 1
fi

exec su-exec photon "$@"
