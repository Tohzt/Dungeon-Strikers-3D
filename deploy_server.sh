#!/usr/bin/env bash
# Upload the game to the droplet and restart its dedicated server.
# Needs the `droplet` host in ~/.ssh/config. Usage: ./deploy_server.sh [-y]
#   -y  skip the confirmation prompts (low memory, protocol version)
set -euo pipefail
cd "$(dirname "$0")"

REMOTE=/opt/dungeon-strikers
ASSUME_YES=0
[[ "${1:-}" == "-y" ]] && ASSUME_YES=1

confirm() {
	((ASSUME_YES)) && return 0
	[[ -t 0 ]] || { echo "Not interactive; rerun with -y to continue anyway." >&2; exit 1; }
	read -rp "$1 [y/N] " reply
	[[ "$reply" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }
}

# --- Pre-flight: droplet resources and the last deployed commit -------------
echo "Checking droplet..."
read -r MEM_MB SWAP_MB DISK_FREE_MB DEPLOYED_COMMIT < <(ssh droplet "
	free -m | awk '/^Mem:/{m=\$2} /^Swap:/{s=\$2} END{printf \"%s %s \", m, s}'
	df -Pm $REMOTE 2>/dev/null | awk 'NR==2{printf \"%s \", \$4}' || printf '0 '
	cat $REMOTE/.deployed_commit 2>/dev/null || echo none
")
[[ "${MEM_MB:-}" =~ ^[0-9]+$ ]] || { echo "Couldn't read droplet resources (is ssh to 'droplet' working?)" >&2; exit 1; }
echo "  RAM ${MEM_MB} MB, swap ${SWAP_MB} MB, ${DISK_FREE_MB} MB free disk"

# The asset import is the memory-hungry step (animated KayKit models), and an
# out-of-memory kill there leaves the server with a half-imported project.
if ((MEM_MB + SWAP_MB < 2000)); then
	echo "WARNING: less than 2 GB of RAM + swap. The asset import may run out of memory."
	echo "  Add a 2 GB swap file on the droplet with:"
	echo "    fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile"
	echo "    echo '/swapfile none swap sw 0 0' >> /etc/fstab"
	confirm "Deploy anyway?"
fi

# Old clients can't talk to a new server if RPCs or synced properties changed,
# so remind to bump PROTOCOL_VERSION when networked code changed since last deploy.
if [[ "$DEPLOYED_COMMIT" != none ]] && git cat-file -e "${DEPLOYED_COMMIT}^{commit}" 2>/dev/null; then
	net_changes=$(git diff "$DEPLOYED_COMMIT" -- '*.gd' '*.tscn' \
		| grep -E '^[+-][^+-]' | grep -cE '@rpc|\brpc(_id)?\(|SceneReplicationConfig|^[+-]properties/' || true)
	old_version=$(git show "$DEPLOYED_COMMIT:net.gd" 2>/dev/null | grep -oP 'PROTOCOL_VERSION := \K\d+' || echo '?')
	new_version=$(grep -oP 'PROTOCOL_VERSION := \K\d+' net.gd)
	echo "  Last deploy: ${DEPLOYED_COMMIT:0:7} (protocol v$old_version), now v$new_version"
	if ((net_changes > 0)) && [[ "$old_version" == "$new_version" ]]; then
		echo "WARNING: $net_changes changed lines touch RPCs or synced properties since the last deploy,"
		echo "  but PROTOCOL_VERSION in net.gd is still $new_version. Old clients may desync with the new server."
		confirm "Deploy without bumping it?"
	fi
else
	echo "  No record of the last deployed commit; skipping the protocol check."
fi

# --- Upload ------------------------------------------------------------------
# Leading slash anchors excludes to the project root. Builds and editor/agent
# folders aren't needed by the headless server.
rsync -az --delete --info=stats1 \
	--exclude /.git/ --exclude /.godot/ --exclude /Exports/ --exclude /_Exports/ \
	--exclude /.cursor/ --exclude /.vscode/ --exclude /.claude/ \
	--exclude /deploy_server.sh --exclude /.deployed_commit --exclude '*.tmp' \
	./ "droplet:$REMOTE/"

# --- Import and restart ------------------------------------------------------
DEPLOY_ID="$(git rev-parse HEAD)"
git diff --quiet HEAD && git diff --quiet --cached HEAD || echo "  (working tree has uncommitted changes; recording HEAD anyway)"

ssh droplet "
	set -e
	# Builds uploaded by older versions of this script before Exports/ was excluded.
	rm -rf $REMOTE/Exports $REMOTE/_Exports
	chown -R dungeon:dungeon $REMOTE
	echo 'Importing assets...'
	log=\$(mktemp)
	code=0
	runuser -u dungeon -- godot --headless --path $REMOTE --import >\"\$log\" 2>&1 || code=\$?
	if [ \$code -ne 0 ]; then
		echo \"Import FAILED (exit \$code).\"
		[ \$code -eq 137 ] && echo 'Exit 137 = killed, almost certainly out of memory. Add swap (see above).'
		tail -n 30 \"\$log\"
		exit 1
	fi
	errors=\$(grep -cE '^(ERROR|SCRIPT ERROR)' \"\$log\" || true)
	[ \"\$errors\" -gt 0 ] && { echo \"Import finished with \$errors errors:\"; grep -E '^(ERROR|SCRIPT ERROR)' \"\$log\" | head -n 10; }
	rm -f \"\$log\"
	systemctl restart dungeon-strikers
	sleep 3
	systemctl is-active dungeon-strikers
	echo $DEPLOY_ID > $REMOTE/.deployed_commit
	journalctl -u dungeon-strikers -n 5 --no-pager -o cat
	echo \"Memory: \$(free -m | awk '/^Mem:/{print \$3\" / \"\$2\" MB used\"}'), server peak \$(systemctl show dungeon-strikers -p MemoryPeak --value | numfmt --to=iec 2>/dev/null || echo n/a)\"
"
