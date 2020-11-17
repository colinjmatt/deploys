#!/bin/bash
# These 2 variables must be single-quoted
transmissionuser='transmission-daemon'
transmissionpass='$transmissionpasssed'

# Destination email and FROM address for emailing any errors
email="$emailsed"
from="$fromsed"

# Time in days to seed for
time=$((86400*21))

# Get list of torrent IDs, then remove and delete if seed time is greater than what $time is set to
torrentlist=$(transmission-remote -n "$transmissionuser":"$transmissionpass" -l | sed -e '1d' -e '$d' | awk '{print $1}' | sed -e 's/[^0-9]*//g')
for id in $torrentlist
do
    seedtime=$(transmission-remote -n "$transmissionuser":"$transmissionpass" -t "$id" -i | grep "Seeding Time" | sed 's/.*(\(.*\) seconds)/\1/')
          if [ "$seedtime" -gt "$time" ]; then
            transmission-remote -n "$transmissionuser":"$transmissionpass" -t "$id" --remove-and-delete
          fi
done

IFS='/'
# Total counted downloads
downloadstotal=$(cd /Media/Downloads/Complete || exit; find -- * -maxdepth 0 | sed "s/^/'/;s/$/'/")

# Acive downloads counted
downloadsactive=$(transmission-remote -n "$transmissionuser":"$transmissionpass" -l | awk -F 'Idle         ' ' {print $2}' | tail -n +2 | head -n -1 | sed "s/^/'/;s/$/'/")

# Any counted downloads that aren't active and can therefore be deleted
downloadstodelete=$(echo "$downloadstotal" | grep -Fxv "$downloadsactive" | tr '\n' ' ')

# Check that the active downloads returned are present in the total downloads counted otherwise there's something wrong with the data
if [ -z "$downloadstodelete" ]; then
  if [ -z "$(echo "$downloadsactive" | grep -Fxv "$downloadstotal")" ]; then
    (cd /Media/Downloads/Complete || exit
    echo "$downloadstodelete" | xargs rm)
  else
    echo "There are no active downloads matched to total downloads. Something is wrong." | \
    mail -s "The Plex download deletion script has failed" \
         -r "$from" \
         "$email"
  fi
fi
unset IFS
