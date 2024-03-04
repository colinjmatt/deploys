#!/bin/bash
# These 2 variables must be single-quoted
transmissionuser='transmission-daemon'
transmissionpass='transmissionpass-sed'
downloads='downloads-sed'

# Time in days to seed for
time=$((86400*21))

# Check if transmission is running. If not, exit so that this script doesn't accidentally remove all downloads
if ! systemctl is-active --quiet transmission-daemon; then 
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
for download in "$downloads"/TV-Shows/* "$downloads"/Films/* "$downloads"/*
do
  if [ -e "$download" ]; then
    downloadstotal="$(cd "$downloads" || exit; find -- * -maxdepth 0 | sed "s/^/'/;s/$/'/" | sed "s/'Films'//g; s/'TV-Shows'//g" | sed '/^$/d')
$(cd "$downloads"/Films || exit; find -- * -maxdepth 0 | sed "s/^/'/;s/$/'/")
$(cd "$downloads"/TV-Shows || exit; find -- * -maxdepth 0 | sed "s/^/'/;s/$/'/")"
    break
  else
    downloadstotal=""
  fi
done

# Active downloads counted
downloadsactive=$(transmission-remote -n "$transmissionuser":"$transmissionpass" -l | head -n -1 | tail -n +2 | awk '$9 != "Finished" {print $0}' | awk -F '  +' '{print $10}' | sed "s/^/'/;s/$/'/")
# Old one in case new one breaks something
# downloadsactive=$(transmission-remote -n "$transmissionuser":"$transmissionpass" -l | grep 'Idle\|Seeding\|Verifying\|Stopped\|Error' | sed -re 's,\s+, ,g' | cut -d ' ' -f 11- | sed "s/^/'/;s/$/'/")

# Any counted downloads that aren't active and can therefore be deleted
downloadstodelete=$(echo "$downloadstotal" | grep -Fxv "$downloadsactive" | tr '\n' ' ')

if [ -n "$downloadstodelete" ]; then
  (cd "$downloads" || exit
  echo "$downloadstodelete" | xargs rm -rf >/dev/null)
  (cd "$downloads"/Films || exit
  echo "$downloadstodelete" | xargs rm -rf >/dev/null)
  (cd "$downloads"/TV-Shows || exit
  echo "$downloadstodelete" | xargs rm -rf >/dev/null)
fi

unset IFS
