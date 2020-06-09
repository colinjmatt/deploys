#!/bin/bash
transmissionuser=''
transmissionpass=''
email=''
from=''
IFS='/'

# Total counted downloads
downloadstotal=$(cd /Media/Downloads/Complete || exit; find -- * -maxdepth 0 | sed "s/^/'/;s/$/'/")

# Acive downloads counted
downloadsactive=$(transmission-remote -n "$transmissionuser":"$transmissionpass" -l | awk -F 'Idle         ' ' {print $2}' | tail -n +2 | head -n -1 | sed "s/^/'/;s/$/'/")

# Any counted downloads that aren't active and can therefore be deleted
downloadstodelete=$(echo "$downloadstotal" | grep -Fxv "$downloadsactive" | tr '\n' ' ')

# Check that the active downloads returned are present in the total downloads counted otherwise there's something wrong with the data
if [ -z "$(echo "$downloadsactive" | grep -Fxv "$downloadstotal")" ]; then
  (cd /Media/Downloads/Complete || exit
  echo "$downloadstodelete" | xargs rm)
else
  echo "There are no active downloads matched to total downloads. Something is wrong." | \
  mail -s "The Plex download deletion script has failed" \
       -r "$from" \
       "$email"
fi

unset IFS
