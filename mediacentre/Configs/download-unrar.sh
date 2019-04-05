#!bin/bash
cd /Media/Downloads/Complete/"$TR_TORRENT_DIR"/
if [[ -f ./*.rar ]]; then
  find *.rar -exec /usr/local/bin/unrar e -r -o- {} \;
fi
