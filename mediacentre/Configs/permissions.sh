#!/bin/bash
chown -R sonarr:sonarr "$tv"
chown -R radarr:radarr	"$films"
chown -R transmission:transmission "$downcomplete"
chmod -R 0777 /Media
