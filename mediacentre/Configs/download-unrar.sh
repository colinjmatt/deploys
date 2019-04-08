#!/bin/bash
torrentdir="$TR_TORRENT_DIR"/"$TR_TORRENT_NAME"
cd "$torrentdir" || return
for archive in ./*.rar
do
  if [[ -e "$archive" ]]; then
    find ./*.rar -exec /usr/local/bin/unrar e -r -o- {} \;
  fi
done
