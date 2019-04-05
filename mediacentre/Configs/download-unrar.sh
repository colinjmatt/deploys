#!/bin/bash
cd /Media/Downloads/Complete/"$TR_TORRENT_DIR"/ || return
for archive in ./*.rar
do
  if [[ -e "$archive" ]]; then
    find ./*.rar -exec /usr/local/bin/unrar e -r -o- {} \;
  fi
done
