#!/bin/bash
chown -R sonarr:sonarr "$tv"
chown -R radarr:radarr	"$films"
chown -R transmission:transmission "$downcomplete"

chmod 777 /Media
chmod -R 770 /Media/*
