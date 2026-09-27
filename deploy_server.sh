#!/usr/bin/env bash
# Upload the game to the droplet and restart its dedicated server.
# Needs the `droplet` host in ~/.ssh/config. Usage: ./deploy_server.sh
set -euo pipefail
cd "$(dirname "$0")"

rsync -az --delete \
	--exclude .git/ --exclude .godot/ --exclude _Exports/ \
	--exclude .cursor/ --exclude .vscode/ --exclude deploy_server.sh \
	./ droplet:/opt/dungeon-strikers/

ssh droplet '
	set -e
	chown -R dungeon:dungeon /opt/dungeon-strikers
	echo "Importing assets..."
	runuser -u dungeon -- godot --headless --path /opt/dungeon-strikers --import >/dev/null 2>&1
	systemctl restart dungeon-strikers
	sleep 3
	systemctl is-active dungeon-strikers
	journalctl -u dungeon-strikers -n 5 --no-pager -o cat
'
