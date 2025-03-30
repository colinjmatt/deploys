#!/bin/bash
# These 2 variables must be single-quoted
transmissionuser='transmission-daemon'
transmissionpass='transmissionpass-sed'
downloads='downloads-sed'

# Time in days to seed for
time=$((86400*21))

# Check if transmission is running. If not, exit so that this script doesn't accidentally remove all downloads
if ! pgrep -f /usr/bin/transmission-daemon; then 
  exit 1
fi

# Remove and delete any torrents that have seeded longer than $time
torrentlist=$(transmission-remote -n "$transmissionuser":"$transmissionpass" -l \
  | sed -e '1d' -e '$d' \
  | awk '{print $1}' \
  | sed -e 's/[^0-9]*//g')

for id in $torrentlist; do
  seedtime=$(transmission-remote -n "$transmissionuser":"$transmissionpass" -t "$id" -i \
    | grep "Seeding Time" \
    | sed 's/.*(\(.*\) seconds)/\1/')

    if [ -n "$seedtime" ]; then
      if [ "$seedtime" -gt "$time" ]; then
        transmission-remote -n "$transmissionuser":"$transmissionpass" -t "$id" --remove-and-delete
      fi
    fi
done

# Remove and delete finished torrents
finishedtorrents=$(transmission-remote -n "$transmissionuser":"$transmissionpass" -l \
  | sed -e '1d' -e '$d' \
  | grep ' Finished ' \
  | awk '{print $1}' \
  | sed -e 's/[^0-9]*//g')

for finid in $finishedtorrents; do
  if [ -n "$finid" ]; then
    transmission-remote -n "$transmissionuser":"$transmissionpass" -t "$finid" --remove-and-delete
  fi
done

IFS='/'
# Total counted downloads
for download in "$downloads"/tv-sonarr/* "$downloads"/films-radarr/* "$downloads"/*
do
  if [ -e "$download" ]; then
    downloadstotal="$(cd "$downloads" || exit; find -- * -maxdepth 0 | sed "s/^/'/;s/$/'/" | sed "s/'films-radarr'//g; s/'tv-sonarr'//g" | sed '/^$/d')
$(cd "$downloads"/films-radarr || exit; find -- * -maxdepth 0 | sed "s/^/'/;s/$/'/")
$(cd "$downloads"/tv-sonarr || exit; find -- * -maxdepth 0 | sed "s/^/'/;s/$/'/")"
    break
  else
    downloadstotal=""
  fi
done

# Active downloads counted
downloadsactive=$(transmission-remote -n "$transmissionuser":"$transmissionpass" -l | head -n -1 | tail -n +2 | awk '$9 != "Finished" {print $0}' | awk -F '  +' '{print $10}' | sed "s/^/'/;s/$/'/")

# Any counted downloads that aren't active and can therefore be deleted
downloadstodelete=$(echo "$downloadstotal" | grep -Fxv "$downloadsactive" | tr '\n' ' ')

if [ -n "$downloadstodelete" ]; then
  (cd "$downloads" || exit
  echo "$downloadstodelete" | xargs rm -rf >/dev/null)
  (cd "$downloads"/films-radarr || exit
  echo "$downloadstodelete" | xargs rm -rf >/dev/null)
  (cd "$downloads"/tv-sonarr || exit
  echo "$downloadstodelete" | xargs rm -rf >/dev/null)
fi

unset IFS
