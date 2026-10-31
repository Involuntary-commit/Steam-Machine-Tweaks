#!/bin/bash
# Caps the Steam Machine's HDMI output at 10-bit color by giving the graphics
# driver an edited copy of the TV's EDID without 12- and 16-bit color.
# Fixes HDR flicker and "No signal" at 4K 120Hz when 12-bit overruns the HDMI 2.1 link.
#
# Usage: sudo bash edid-10bpc.sh status|test|test-revert|install|uninstall
#   status       show which color depths the TV lists and what the link uses
#   test         use the 10-bit EDID until the next restart (then replug HDMI)
#   test-revert  go back to the TV's own EDID without restarting (then replug HDMI)
#   install      use the 10-bit EDID at every startup
#   uninstall    remove everything that install added
# If the TV is not on HDMI-A-1, set CONNECTOR, for example: sudo CONNECTOR=HDMI-A-2 bash edid-10bpc.sh status
set -euo pipefail

CONNECTOR=${CONNECTOR:-HDMI-A-1}
HERE=$(cd "$(dirname "$0")" && pwd)
PATCHER=$HERE/edid-10bpc.py
FWDIR=/etc/firmware-edid
FWREL=edid/$CONNECTOR-10bpc.bin
FW=$FWDIR/$FWREL
ORIG=$FWDIR/original-$CONNECTOR.bin
MKI=/etc/mkinitcpio.conf.d/90-edid-10bpc.conf
GRUBD=/etc/default/grub.d/edid-10bpc.cfg
KEEP=/etc/atomic-update.conf.d/edid-10bpc.conf
GRUBCFG=/efi/EFI/steamos/grub.cfg

log() { echo "$*"; }
die() { echo "error: $*" >&2; exit 1; }
need_root() { [ "$(id -u)" = 0 ] || die "this needs administrator rights. Put sudo in front of the command."; }

sysfs_edid() {
	local f
	for f in /sys/class/drm/card*-"$CONNECTOR"/edid; do
		[ -s "$f" ] && { echo "$f"; return; }
	done
	die "no EDID found on $CONNECTOR. Is the TV on and connected? (See \"TV on a different port\" in the README.)"
}

debugfs_dir() {
	local d
	for d in /sys/kernel/debug/dri/*/"$CONNECTOR"; do
		[ -e "$d/edid_override" ] && { echo "$d"; return; }
	done
	die "this kernel does not offer a temporary EDID override for $CONNECTOR"
}

# grep without -q reads all input, so pipefail never sees a SIGPIPE.
cmdline_has() { tr ' ' '\n' < /proc/cmdline | grep "^$1" >/dev/null; }

# Keep $ORIG as the connected display's own EDID. While an override is loaded the
# sysfs copy is the edited one, so it only replaces $ORIG when it is not simply
# the patched version of it (a different display, or no override at all).
save_original() {
	local cur tmp
	if cmdline_has drm.edid_firmware=; then
		[ -s "$ORIG" ] || die "an EDID override is active, but the backup $ORIG is missing. Run uninstall, restart, then try again."
		return
	fi
	cur=$(sysfs_edid)
	if [ -s "$ORIG" ]; then
		tmp=$(mktemp)
		python3 -I "$PATCHER" "$ORIG" "$tmp" >/dev/null
		if cmp -s "$cur" "$ORIG" || cmp -s "$cur" "$tmp"; then
			rm -f "$tmp"; return
		fi
		rm -f "$tmp"
	fi
	install -Dm644 "$cur" "$ORIG"
	log "Saved a backup of the TV's own EDID to $ORIG"
}

make_patched() {
	local out=$1
	python3 -I "$PATCHER" "$ORIG" "$out"
	python3 -I "$PATCHER" --report "$out" >/dev/null || die "the edited EDID still lists 12-bit color. Nothing was changed."
}

check_steamos() {
	# shellcheck source=/dev/null
	( . /etc/os-release; [ "${ID:-}" = steamos ] ) || die "this script only supports SteamOS"
	[ -d /etc/default/grub.d ] || die "/etc/default/grub.d not found"
	command -v mkinitcpio >/dev/null || die "mkinitcpio not found"
}

check_conflicts() {
	local p
	for p in firmware_class.path drm.edid_firmware; do
		if grep -rqs "$p=" /etc/default/grub /etc/default/grub.d --exclude="$(basename "$GRUBD")"; then
			die "another boot setting already uses $p. Nothing was changed, to avoid overriding it."
		fi
	done
}

rebuild_boot() {
	local rc=0 img found=0
	steamos-readonly disable
	trap 'steamos-readonly enable' EXIT
	# SteamOS's mkinitcpio reports a harmless "module not found: blake2b_generic"
	# and exits 1 even though it writes the image, so judge by the image itself.
	mkinitcpio -P || rc=$?
	steamos-readonly enable
	trap - EXIT
	for img in /boot/initramfs-*.img; do
		[ -s "$img" ] || continue
		if [ -s "$FW" ]; then
			if lsinitcpio "$img" 2>/dev/null | grep "${FW#/}" >/dev/null; then
				found=1; log "OK: EDID is in $img"
			else
				log "WARNING: the edited EDID is not in $img"
			fi
		fi
	done
	if [ -s "$FW" ] && [ "$found" = 0 ]; then
		die "the boot image rebuild failed (mkinitcpio exit code $rc), and no boot image contains the edited EDID"
	fi
	[ "$rc" = 0 ] || log "(mkinitcpio reported exit code $rc, but the boot image was written. This is normal on SteamOS.)"
	update-grub
}

# Prints the pixel format and color depth of the live HDMI 2.1 (FRL) link,
# read from the display driver's HPO table, for example "4:4:4, 12-bit".
link_depth() {
	local line
	line=$(grep -A1 "^HPO:" /sys/kernel/debug/dri/*/amdgpu_dm_dtn_log 2>/dev/null | tail -1 || true)
	[ -n "$line" ] || return 0
	echo "$line" | awk '{ for (i = 1; i < NF; i++) if ($i ~ /^4:[024]:[024]$/) { print $i ", " $(i + 1) "-bit"; exit } print "unknown (" $0 ")" }'
}

cmd_status() {
	local edid link listed
	edid=$(sysfs_edid)
	log "Connector:      $CONNECTOR"
	if cmdline_has drm.edid_firmware=; then
		log "Boot override:  installed and active"
	elif [ -f "$GRUBD" ]; then
		log "Boot override:  installed, active after the next restart"
	else
		log "Boot override:  not installed"
	fi
	log "EDID in use:"
	listed=0
	python3 -I "$PATCHER" --report "$edid" | sed 's/^/  /' || listed=1
	if [ "$(id -u)" = 0 ]; then
		link=$(link_depth)
		log "HDMI 2.1 link:  ${link:-not in use}"
	else
		log "HDMI 2.1 link:  (run with sudo to see it)"
	fi
	if [ "$listed" = 1 ]; then
		log "Result: the TV lists 12-bit color, so the driver can pick it. The fix is not active."
	else
		log "Result: 12-bit color is not listed, so the link stays at 10-bit or below. The fix is active."
	fi
}

cmd_test() {
	need_root
	local d tmp
	d=$(debugfs_dir)
	save_original
	tmp=$(mktemp)
	make_patched "$tmp"
	cat "$tmp" > "$d/edid_override"
	rm -f "$tmp"
	log "The 10-bit EDID is active until the next restart. Unplug the HDMI cable for 5 seconds, plug it back in, then run: sudo bash $0 status"
}

cmd_test_revert() {
	need_root
	local d
	d=$(debugfs_dir)
	[ -s "$ORIG" ] || die "no backup of the TV's own EDID was found. Restart the Steam Machine instead."
	# This kernel rejects "reset", so write the TV's own EDID back.
	cat "$ORIG" > "$d/edid_override"
	log "The TV's own EDID is back. Unplug the HDMI cable for 5 seconds and plug it back in (or restart)."
}

cmd_install() {
	need_root
	check_steamos
	check_conflicts
	save_original
	install -d "$(dirname "$FW")"
	make_patched "$FW"
	chmod 644 "$FW"
	echo "FILES+=($FW)" > "$MKI"
	cat > "$GRUBD" <<EOF
# 10-bit EDID override for $CONNECTOR (removes 12- and 16-bit color). Managed by edid-10bpc.sh.
GRUB_CMDLINE_LINUX_DEFAULT="\${GRUB_CMDLINE_LINUX_DEFAULT} firmware_class.path=$FWDIR drm.edid_firmware=$CONNECTOR:$FWREL"
EOF
	printf '%s\n' "# Keep the 10-bit EDID override across SteamOS updates." "$FW" "$ORIG" "$MKI" "$GRUBD" > "$KEEP"
	rebuild_boot
	if grep -qs "drm.edid_firmware=$CONNECTOR" "$GRUBCFG"; then
		log "OK: boot option is set"
	else
		log "WARNING: the boot option was not found in $GRUBCFG"
	fi
	log "Done. Restart the Steam Machine, then run: sudo bash $0 status"
}

cmd_uninstall() {
	need_root
	check_steamos
	rm -f "$FW" "$MKI" "$GRUBD" "$KEEP"
	rmdir "$(dirname "$FW")" 2>/dev/null || true
	rebuild_boot
	log "Removed. Restart the Steam Machine to go back to the TV's own EDID. (The backup stays at $ORIG.)"
}

case "${1:-}" in
	status) cmd_status ;;
	test) cmd_test ;;
	test-revert) cmd_test_revert ;;
	install) cmd_install ;;
	uninstall) cmd_uninstall ;;
	*) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
