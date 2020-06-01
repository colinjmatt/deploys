#!/bin/bash
transmissionuser=''
transmissionpass=''
# Total counted downloads
downloadstotal=$(ls /Media/Downloads/Complete)

# Acive downloads counted
downloadsactive=$(transmission-remote -n "$transmissionuser":"$transmissionpass" -l | awk -F ' ' ' {print $10}')

# Any counted downloads that aren't active and can therefore be deleted
downloadstodelete=$(echo "$downloadstotal" | grep -Fxv "$downloadsactive")

# Check that the active downloads returned are present in the total downloads counted otherwise there's something wrong
if [ -z "$(echo "$downloadsactive" | grep -Fxv "$downloadstotal")" ]; then
  for download in $downloadstodelete; do
    rm -rf "/Media/Downloads/Complete/$download"
  done
else
  echo "There are no active downloads matched to total downloads. Something is wrong" | \
  mail -s "The Plex download deletion script has failed" postmaster@matthews-co.uk
fi
