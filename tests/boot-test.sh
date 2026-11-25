#!/usr/bin/env bash
# Install a Stiloria image to a disk, as `bootc install` does on a real
# machine, start it in a VM, and have it check itself (tests/boot-check.sh).
# The build's own checks stop at the image's files; this one finds an image
# that doesn't boot, or boots without its login screen, before it is published.
#
#   tests/boot-test.sh [IMAGE]        default: localhost/stiloria:latest
#
# IMAGE is a local image, as `just build` leaves it. Installing needs root:
# the script calls sudo for that part (copying the image into root's podman if
# it is only in yours, and `bootc install`); the VM runs as you. It needs KVM,
# QEMU and the UEFI firmware (Fedora: qemu-kvm edk2-ovmf; Ubuntu:
# qemu-system-x86 ovmf), both of which Stiloria includes.
#
# The VM has no network, so nothing in it downloads or updates anything, and
# no user account: it is checked up to the login screen. The checks reach it
# as systemd credentials on the VM's firmware, so the disk holds exactly the
# image, nothing added for the test.
#
#   BOOT_TEST_DIR      where the disk and logs go (default: a new folder in
#                      /var/tmp, removed afterwards unless the test fails)
#   BOOT_TEST_TIMEOUT  seconds the VM may take (default 1200)
#   BOOT_TEST_KEEP=1   keep the disk, to start it again by hand
set -euo pipefail

image=${1:-localhost/stiloria:latest}
timeout=${BOOT_TEST_TIMEOUT:-1200}
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

die() {
    echo "boot-test: $*" >&2
    exit 1
}
as_root() {
    if ((EUID == 0)); then "$@"; else sudo "$@"; fi
}

### What the host needs
qemu=
for candidate in qemu-system-x86_64 qemu-kvm /usr/libexec/qemu-kvm; do
    if command -v "$candidate" > /dev/null; then
        qemu=$(command -v "$candidate")
        break
    fi
done
[[ -n $qemu ]] || die "QEMU isn't installed (qemu-system-x86_64)"
# UEFI firmware and its blank variable store, as each distribution names them.
firmware=
for pair in /usr/share/edk2/ovmf/OVMF_CODE.fd:/usr/share/edk2/ovmf/OVMF_VARS.fd \
    /usr/share/OVMF/OVMF_CODE_4M.fd:/usr/share/OVMF/OVMF_VARS_4M.fd \
    /usr/share/edk2/x64/OVMF_CODE.4m.fd:/usr/share/edk2/x64/OVMF_VARS.4m.fd; do
    if [[ -f ${pair%%:*} && -f ${pair##*:} ]]; then
        firmware=$pair
        break
    fi
done
[[ -n $firmware ]] || die "the UEFI firmware for VMs isn't installed (edk2-ovmf, or ovmf)"
[[ -r /dev/kvm && -w /dev/kvm ]] || die "/dev/kvm isn't usable here; without KVM the VM would take hours"
for tool in podman truncate base64 timeout; do
    command -v "$tool" > /dev/null || die "$tool isn't installed"
done

if [[ -n ${BOOT_TEST_DIR:-} ]]; then
    work=$BOOT_TEST_DIR
    mkdir -p "$work"
    made_work=
else
    # Not /tmp: the disk is tens of gigabytes, and /tmp is often memory.
    work=$(mktemp -d -p /var/tmp stiloria-boot-test.XXXXXX)
    made_work=1
fi
work=$(cd "$work" && pwd)
disk=$work/disk.raw
serial=$work/serial.log
rm -f "$disk" "$serial" "$work/vars.fd"

passed=
cleanup() {
    [[ -n ${qemu_pid:-} ]] && kill "$qemu_pid" 2> /dev/null || true
    rm -f "$work/image.tar"
    if [[ -z ${BOOT_TEST_KEEP:-} ]]; then
        rm -f "$disk" "$work/vars.fd"
        # A folder made here goes too, unless its log is still needed.
        if [[ -n $made_work && -n $passed ]]; then
            rm -rf "$work"
        fi
    fi
}
trap cleanup EXIT

### The image, in root's podman
# `bootc install` runs in a root container of the image it installs. An image
# built as a user is in that user's podman: copy it over, unless root already
# has this very image.
echo "==> Installing $image to $disk"
# Ask for sudo here, once, where a refusal reads as what it is.
as_root true || die "installing needs root, and sudo didn't grant it"
user_id=
if ((EUID != 0)); then
    user_id=$(podman image inspect --format '{{.Id}}' "$image" 2> /dev/null || true)
fi
root_id=$(as_root podman image inspect --format '{{.Id}}' "$image" 2> /dev/null || true)
if [[ -n $user_id && $user_id != "$root_id" ]]; then
    echo "==> Copying $image into root's podman"
    podman save --output "$work/image.tar" "$image"
    as_root podman load --input "$work/image.tar"
    rm -f "$work/image.tar"
elif [[ -z $root_id ]]; then
    die "there is no local image $image (build it with \`just build\`, or pull it with \`sudo podman pull\`)"
fi

### Install to a disk
# The disk is a sparse file: it takes only the space the image fills. bootc
# partitions it the way the image asks (Bazzite: btrfs) and leaves it ready to
# start on any machine's UEFI (--generic-image). The serial console is for
# this test's log; it changes nothing in the image.
truncate -s "${BOOT_TEST_DISK_SIZE:-40G}" "$disk"
as_root podman run --rm --privileged --pid=host \
    --security-opt label=type:unconfined_t \
    -v /dev:/dev \
    -v /var/lib/containers:/var/lib/containers \
    -v "$work":/output \
    "$image" \
    bootc install to-disk --via-loopback --generic-image --wipe \
    --karg console=tty0 --karg console=ttyS0,115200n8 \
    /output/disk.raw

### The checks, handed to the VM's systemd
# QEMU puts these in the firmware's SMBIOS strings, and systemd reads them as
# credentials: the two it knows as an extra unit and a drop-in make
# multi-user.target start stiloria-boot-test.service, which runs boot-check.sh
# from the third.
unit=$work/stiloria-boot-test.service
cat > "$unit" << 'EOF'
[Unit]
Description=Stiloria's boot test (tests/boot-check.sh)
# The initrd gets this unit too; the test is for the installed system.
ConditionPathExists=!/etc/initrd-release

[Service]
Type=exec
Environment=BOOT_TEST_VM=1
ImportCredential=stiloria.boot-check
ExecStart=/usr/bin/bash %d/stiloria.boot-check
EOF
dropin=$work/multi-user.target.conf
printf '[Unit]\nWants=stiloria-boot-test.service\n' > "$dropin"
credentials=()
credential() {
    credentials+=(-smbios "type=11,value=io.systemd.credential.binary:$1=$(base64 -w0 "$2")")
}
credential systemd.extra-unit.stiloria-boot-test.service "$unit"
credential systemd.unit-dropin.multi-user.target "$dropin"
credential stiloria.boot-check "$here/boot-check.sh"

### Start it
cpus=$(nproc)
((cpus > 4)) && cpus=4
cp "${firmware##*:}" "$work/vars.fd"
: > "$serial"
echo "==> Starting the VM (up to $((timeout / 60)) minutes); its console is in $serial"
# The check lines, wherever they are in the console's output.
check_lines() { LC_ALL=C sed "$@" -n 's/\r$//; s/^.*\(BOOT-CHECK .*\)$/\1/p'; }
status=0
timeout "$timeout" "$qemu" \
    -name stiloria-boot-test \
    -machine q35,accel=kvm -cpu host -smp "$cpus" -m "${BOOT_TEST_MEMORY:-4G}" \
    -drive "if=pflash,format=raw,readonly=on,file=${firmware%%:*}" \
    -drive "if=pflash,format=raw,file=$work/vars.fd" \
    -drive "file=$disk,format=raw,if=virtio,cache=unsafe" \
    -vga none -device virtio-vga -display none \
    -device virtio-rng-pci \
    -nic none \
    -serial "file:$serial" -monitor none \
    "${credentials[@]}" &
qemu_pid=$!
# Show each check as it reports; tail stops when the VM does.
tail --pid="$qemu_pid" -n +1 -f "$serial" 2> /dev/null | check_lines -u &
wait "$qemu_pid" || status=$?
qemu_pid=
wait || true

### The verdict
results=$(check_lines < "$serial")
verdict=$(grep 'BOOT-CHECK RESULT: ' <<< "$results" | tail -n 1 || true)
if [[ $verdict == "BOOT-CHECK RESULT: PASS" ]]; then
    passed=1
    summary="$image boots: every check passed"
elif [[ -n $verdict ]]; then
    summary="$image boots, but fails its checks"
elif ((status == 124)); then
    summary="$image didn't finish booting in $((timeout / 60)) minutes"
else
    summary="the VM stopped (QEMU's exit status: $status) before $image reported"
fi

echo
echo "==> $summary"
if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then
    {
        echo "### Boot test: $summary"
        echo
        echo '```'
        echo "${results:-No check reported.}"
        echo '```'
    } >> "$GITHUB_STEP_SUMMARY"
fi
if [[ -z $passed ]]; then
    echo "==> The end of the VM's console ($serial):"
    tail -n 80 "$serial" | LC_ALL=C sed 's/\r$//; s/\x1b\[[0-9;?]*[A-Za-z]//g'
    exit 1
fi
