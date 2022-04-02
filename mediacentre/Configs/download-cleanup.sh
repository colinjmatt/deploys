#!/bin/bash
# These 2 variables must be single-quoted
transmissionuser='transmission-daemon'
transmissionpass='transmissionpasssed'
downloads='downloadssed'

# Time in days to seed for
time=$((86400*21))

torrentlist=$(transmission-remote -n "$transmissionuser":"$transmissionpass" -l | sed -e '1d' -e '$d' | awk '{print $1}' | sed -e 's/[^0-9]*//g')
for id in $torrentlist
do
  seedtime=$(transmission-remote -n "$transmissionuser":"$transmissionpass" -t "$id" -i | grep "Seeding Time" | sed 's/.*(\(.*\) seconds)/\1/')
    if [ -n "$seedtime" ]; then
      if [ "$seedtime" -gt "$time" ]; then
        transmission-remote -n "$transmissionuser":"$transmissionpass" -t "$id" --remove-and-delete
      fi
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
downloadsactive=$(transmission-remote -n "$transmissionuser":"$transmissionpass" -l | grep 'Idle\|Seeding\|Verifying\|Stopped' | sed -re 's,\s+, ,g' | cut -d ' ' -f 11- | sed "s/^/'/;s/$/'/")

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
