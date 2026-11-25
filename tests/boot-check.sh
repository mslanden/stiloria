#!/usr/bin/bash
# What a booted Stiloria must get right, checked from inside it.
# tests/boot-test.sh runs this in a freshly installed VM; it also runs on any
# installed machine, as any user in the wheel group, changing nothing:
#
#   tests/boot-check.sh
#
# Each check prints one line, "BOOT-CHECK ok: …", "BOOT-CHECK FAIL: …" or
# "BOOT-CHECK warn: …", and the last line is "BOOT-CHECK RESULT: PASS" or
# "BOOT-CHECK RESULT: FAIL". A warning doesn't fail the test: it is for things
# worth reading that a VM without a network can't judge, and "BOOT-CHECK note: …"
# says a first boot restarted itself before the checks finished. In the test VM
# (BOOT_TEST_VM=1, set by the unit boot-test.sh adds) the lines also go to the
# serial port, where boot-test.sh reads them, and the VM powers off at the end.
set -uo pipefail

vm=${BOOT_TEST_VM:-}
failed=0
finished=

say() {
    echo "BOOT-CHECK $*"
    [[ -z $vm ]] || echo "BOOT-CHECK $*" > /dev/ttyS0
}
ok() { say "ok: $*"; }
warn() { say "warn: $*"; }
fail() {
    say "FAIL: $*"
    failed=1
}
# check "what must hold" command…: the command's output is the reason it failed.
check() {
    local what=$1 out
    shift
    if out=$("$@" 2>&1); then
        ok "$what"
    else
        out=${out//$'\n'/ | }
        fail "$what${out:+: ${out:0:300}}"
    fi
}
# Whatever happens, boot-test.sh gets a result line and the VM stops.
finish() {
    # A first boot may restart itself: Bazzite's hardware setup does, to apply
    # its kernel arguments. This unit is stopped with everything else, and the
    # checks are for the boot that follows.
    if [[ -n $vm && -z $finished && $(systemctl is-system-running) == stopping ]]; then
        say "note: the system is restarting itself; the checks run on the next boot"
        return
    fi
    if [[ -z $finished ]]; then
        fail "boot-check.sh stopped before its last check"
    fi
    if ((failed)); then
        if [[ -n $vm ]]; then
            {
                echo "--- failed units"
                systemctl --failed --no-legend --plain
                echo "--- errors this boot"
                journalctl -b -p 3 -q --no-pager -n 60
            } > /dev/ttyS0 2>&1
        fi
        say "RESULT: FAIL"
    else
        say "RESULT: PASS"
    fi
    [[ -z $vm ]] || systemctl poweroff
}
trap finish EXIT

### It boots, all the way to the login screen
# The unit that runs this in the VM starts with multi-user.target, before the
# desktop's: wait for it.
for _ in $(seq 120); do
    systemctl is-active -q graphical.target && break
    sleep 5
done
check "the system reached graphical.target" systemctl is-active graphical.target
# The first boot's own jobs (hardware setup, tmpfiles, Stiloria's services),
# then a moment for a login screen that crashes to do so.
for _ in $(seq 60); do
    [[ $(systemctl is-system-running) != starting ]] && break
    sleep 5
done
[[ -z $vm ]] || sleep 20
state=$(systemctl is-system-running)
if [[ $state == starting ]]; then
    warn "still starting after 5 minutes: $(systemctl list-jobs --no-legend --plain | awk '{print $2}' | tr '\n' ' ')"
fi

display_manager=$(systemctl show -P Id display-manager.service)
check "the login screen's service is running ($display_manager)" systemctl is-active display-manager.service
restarts=$(systemctl show -P NRestarts display-manager.service)
if [[ $restarts == 0 ]]; then
    ok "the login screen's service never restarted"
else
    fail "the login screen's service restarted $restarts times"
fi
# The login screen itself is a session of class "greeter"; on a machine
# someone is using, their session stands in for it.
on_screen() {
    loginctl list-sessions --json=short |
        jq -e --arg vm "$vm" 'any(.[]; .class == "greeter" or ($vm == "" and .class == "user"))' > /dev/null
}
for _ in $(seq 12); do
    on_screen && break
    sleep 5
done
check "a login screen (or a desktop) is on a seat" on_screen

### It is Stiloria, installed the way updates expect
check "it calls itself Stiloria" grep -qx 'PRETTY_NAME="Stiloria"' /usr/lib/os-release
image=$(rpm-ostree status --json --booted | jq -r '.deployments[0]."container-image-reference" // ""')
if [[ -z $image ]]; then
    fail "the booted system doesn't come from a container image"
elif [[ $image == ostree-image-signed:* ]]; then
    ok "it tracks a signed image: $image"
else
    warn "it tracks $image, which isn't verified (stiloria-signed-tracking moves Stiloria's own images to signed tracking)"
fi
check "SELinux is enforcing" test "$(getenforce)" = Enforcing

### What only a boot sets up: tmpfiles links and folders in /var
# /opt is /var/opt, which the image fills only once: Vivaldi lives in
# /usr/lib/opt, and stiloria-vivaldi.conf links it at each boot.
check "Vivaldi is at /opt/vivaldi" test -x /opt/vivaldi/vivaldi
# libvirt and swtpm keep their state in /var (stiloria-libvirt.conf makes the
# folders), and their daemons start when something connects.
check "swtpm's certificate folder exists" test -d /var/lib/swtpm-localca
check "libvirt answers on qemu:///system" timeout 120 virsh -c qemu:///system list --all

### Stiloria's own services
for unit in stiloria-flatpak-manager.service stiloria-signed-tracking.service; do
    check "$unit is enabled" systemctl is-enabled "$unit"
done
# It only reads the tracked image when there is nothing for it to change.
result=$(systemctl show -P Result stiloria-signed-tracking.service)
if [[ $result == success ]]; then
    ok "stiloria-signed-tracking has not failed"
else
    fail "stiloria-signed-tracking: $result"
fi
if [[ -x /usr/bin/achilles ]]; then
    check "Achilles starts at login" test -f /etc/xdg/autostart/achilles.desktop
else
    warn "this image was built without Achilles"
fi

### Worth reading, but not a verdict: without a network some units fail in a
# VM that work on a real machine.
failed_units=$(systemctl --failed --no-legend --plain | awk '{print $1}' | tr '\n' ' ')
if [[ -n ${failed_units// /} ]]; then
    warn "failed units: $failed_units"
else
    ok "no failed units"
fi

finished=1
exit "$failed"
