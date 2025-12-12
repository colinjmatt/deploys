#!/bin/bash
set -euo pipefail

# ===== Config =====
transmissionuser='transmission'
transmissionpass='transmissionpass-sed'

downloads='/downloads'
incomplete='/downloads/incomplete'

# Time in seconds to seed for (21 days)
seed_seconds=$((86400*21))

# Set to 1 to preview actions only
DRY_RUN=1

tr() {
  transmission-remote -n "${transmissionuser}:${transmissionpass}" "$@"
}

rm_safe() {
  # $@ are paths (can contain spaces)
  if (( DRY_RUN )); then
    printf '[DRY RUN] rm -rf -- %q\n' "$@"
  else
    rm -rf -- "$@"
  fi
}

# ===== Safety: ensure transmission-daemon is running =====
if ! pgrep -f '/usr/bin/transmission-daemon' >/dev/null 2>&1; then
  echo "transmission-daemon not running; refusing to run."
  exit 1
fi

# ===== 1) Remove torrents seeded longer than seed_seconds =====
# Get numeric torrent IDs
mapfile -t torrent_ids < <(tr -l | sed '1d;$d' | awk '{print $1}' | sed 's/[^0-9]//g' | sed '/^$/d')

for id in "${torrent_ids[@]}"; do
  # Extract seeding time in seconds (robust-ish: find line, then pull (...) seconds)
  seedtime="$(tr -t "$id" -i | awk -F'[()]' '/Seeding Time/ {print $2}' | awk '{print $1}' || true)"

  if [[ -n "${seedtime}" ]] && [[ "${seedtime}" =~ ^[0-9]+$ ]]; then
    if (( seedtime > seed_seconds )); then
      if (( DRY_RUN )); then
        echo "[DRY RUN] Would remove+delete torrent id ${id} (seeded ${seedtime}s)"
      else
        tr -t "$id" --remove-and-delete
      fi
    fi
  fi
done

# ===== 2) Remove finished torrents (status exactly "Finished") =====
# Instead of grep on the whole line, filter by the Status column reliably.
# Transmission's -l output columns are not perfectly stable, but Status is near the end.
# We'll take the last column as Status and compare to "Finished".
mapfile -t finished_ids < <(
  tr -l | sed '1d;$d' |
  awk '{
    id=$1;
    status=$NF;
    gsub(/[^0-9]/,"",id);
    if (id != "" && status == "Finished") print id
  }'
)

for id in "${finished_ids[@]}"; do
  if (( DRY_RUN )); then
    echo "[DRY RUN] Would remove+delete finished torrent id ${id}"
  else
    tr -t "$id" --remove-and-delete
  fi
done

# ===== 3) Delete orphaned items on disk that Transmission no longer knows about =====
# Build a set of torrent names Transmission currently knows (not just “active”)
# Use the Name field from -l by taking everything after the Status column.
# This is still a little annoying with spacing, so we’ll instead query each torrent for its Name.
declare -A known_names=()

for id in "${torrent_ids[@]}"; do
  name="$(tr -t "$id" -i | awk -F': ' '/^ *Name:/ {print $2; exit}' || true)"
  [[ -n "$name" ]] && known_names["$name"]=1
done

# Helper: list immediate children (files/dirs) in a folder
list_children() {
  local dir="$1"
  [[ -d "$dir" ]] || return 0
  find "$dir" -mindepth 1 -maxdepth 1 -print0
}

# Build a list of candidates under /downloads (excluding your known “structure” dirs)
# Adjust exclusions to match your actual layout.
declare -a delete_paths=()

while IFS= read -r -d '' path; do
  base="$(basename "$path")"

  # Hard exclusions – NEVER delete these
  case "$path" in
    "$incomplete"|"${incomplete}/"*) continue ;;
  esac

  # Skip known structural directories
  case "$base" in
    "complete"|"films-radarr"|"tv-sonarr") continue ;;
  esac

  # Only delete if Transmission does not know about it
  if [[ -z "${known_names[$base]+x}" ]]; then
    delete_paths+=("$path")
  fi
done < <(list_children "$downloads")

if ((${#delete_paths[@]})); then
  echo "Orphaned items to delete under ${downloads}:"
  printf '  %q\n' "${delete_paths[@]}"
  rm_safe "${delete_paths[@]}"
else
  echo "No orphaned items found under ${downloads}."
fi