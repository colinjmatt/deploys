#!/bin/bash
chown -R sonarr:sonarr /Media/TV\ Shows
chown -R radarr:radarr	/Media/Films
chown -R transmission:transmission /Media/Downloads
chmod -R 0777 /Media
