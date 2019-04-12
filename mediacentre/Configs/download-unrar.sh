#!/bin/bash
torrentdir="$TR_TORRENT_DIR"/"$TR_TORRENT_NAME"
cd "$torrentdir" || return
for archive in ./*.rar
do
    /usr/local/bin/unrar e -r -o- "$archive"
done
