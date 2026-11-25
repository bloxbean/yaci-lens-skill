#!/usr/bin/env bash
# Run SQL against the public Cardano lake (Yaci Lens data) with the DuckDB CLI.
#
#   scripts/query.sh "SELECT count(*) FROM block WHERE date = DATE '2026-11-24'"
#   scripts/query.sh -f query.sql
#   scripts/query.sh -csv "SELECT ..."        # CSV output (default: DuckDB box mode)
#   scripts/query.sh -json "SELECT ..."       # JSON output
#
# The catalog is attached as `lake` (the default database, so `block` = `lake.block`) and as `lake_meta`
# (DuckLake metadata tables). Env: LENS_CATALOG_URL, LENS_SUMMARY_URL, DUCKDB (path to the CLI).
set -euo pipefail

CATALOG=${LENS_CATALOG_URL:-https://data.bloxbean.org/mainnet/v1/catalog.ducklake}
SUMMARY=${LENS_SUMMARY_URL:-https://data.bloxbean.org/mainnet/v1/summary/}
DUCKDB=${DUCKDB:-$(command -v duckdb || true)}

if [ -z "$DUCKDB" ]; then
  echo "duckdb CLI not found. Install DuckDB 1.5+ (https://duckdb.org/docs/installation/) or set DUCKDB=/path/to/duckdb" >&2
  exit 2
fi
ver=$("$DUCKDB" --version | awk '{print $1}' | tr -d v)
major=${ver%%.*}; rest=${ver#*.}; minor=${rest%%.*}
if [ "$major" -lt 1 ] || { [ "$major" -eq 1 ] && [ "$minor" -lt 5 ]; }; then
  echo "DuckDB $ver is too old for the catalog; need 1.5 or newer" >&2
  exit 2
fi

mode=(-box)
sql=""
while [ $# -gt 0 ]; do
  case "$1" in
    -csv) mode=(-csv); shift ;;
    -json) mode=(-json); shift ;;
    -line) mode=(-line); shift ;;
    -f) sql=$(cat "$2"); shift 2 ;;
    *) sql="$1"; shift ;;
  esac
done
[ -n "$sql" ] || { echo "usage: $0 [-csv|-json|-line] \"SQL\" | -f file.sql" >&2; exit 2; }

"$DUCKDB" "${mode[@]}" -bail <<SQL
INSTALL ducklake; LOAD ducklake;
SET TimeZone = 'UTC';
SET VARIABLE summary = '${SUMMARY}';
ATTACH '${CATALOG}' AS lake (TYPE ducklake, READ_ONLY);
ATTACH '${CATALOG}' AS lake_meta (READ_ONLY);
USE lake;
${sql}
SQL
