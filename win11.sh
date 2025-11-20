#!/usr/bin/env bash
set -e -u

# Assign the device $1 to the driver $2. Assumes the device has no driver.
bind() {
    local device="/sys/bus/pci/devices/$1"
    local driver="/sys/bus/pci/drivers/$2"
    [ -e "$driver" ] || modprobe "$2"
    local device_id vendor_id
    device_id=$(cat "$device/device")
    vendor_id=$(cat "$device/vendor")
    if echo $vendor_id $device_id 1>"$driver/new_id" 2>/dev/null; then
        # In this case the kernel binds the driver for us.
        true
    else
        echo "$1" > "$driver/bind"
    fi
}
# Remove the device $1 from its driver. Do nothing if it has no driver.
unbind() {
    local device="/sys/bus/pci/devices/$1"
    [ -e "$device/driver" ] || return 0
    echo "Unbinding $1 from current driver"
    echo "$1" > "$device/driver/unbind"
}

devices=(0000:03:00.0 0000:03:00.1 0000:03:00.2 0000:03:00.3)
# Restore the original drivers before the program exits. Without this the GPU
# and Linux terminal are unusable.
cleanup() {
    for device in "${devices[@]}"; do
        echo 1 > "/sys/bus/pci/devices/$device/remove"
    done
    echo 1 > /sys/bus/pci/rescan
}
if (( "${VFIO:-}" )); then
    trap cleanup EXIT
    for device in "${devices[@]}"; do
        unbind "$device"
        bind "$device" vfio-pci
    done
fi

args=(
    -vnc :0,password=off # no graphical QEMU
    -chardev stdio,id=char0 -mon chardev=char0,mode=readline
    -machine q35,accel=kvm,usb=off -nodefaults -boot menu=on
    -cpu host,$(
        hyperv=(
            hv_relaxed hv_vapic hv_spinlocks=0x1FFF hv_vpindex hv_runtime
            hv_time hv_synic hv_stimer hv_tlbflush hv_vendor_id=XYZ
            hv_frequencies hv_xmm_input
        )
        IFS="," # separate statement required
        echo "${hyperv[*]}" # quotes required
    )
    -rtc base=localtime,driftfix=slew
    -device qemu-xhci -device usb-tablet
    -nic user,model=virtio -vga virtio -device virtio-balloon
    -drive media=disk,if=virtio,file=win11.qcow2
    -drive media=cdrom,readonly=on,file=Win11_25H2_English_x64.iso
    -drive media=cdrom,readonly=on,file=virtio-win-0.1.285.iso
    -drive media=cdrom,readonly=on,file=unattend.iso
)
if (( "${VFIO:-}" )); then
    args+=(
        -smp 8,cores=8 -m 24G -overcommit mem-lock=on
        -device pcie-root-port,id=pcie.1,bus=pcie.0 # used by VFIO
        -device vfio-pci,host=03:00.0,bus=pcie.1,multifunction=on
        -device vfio-pci,host=03:00.1,bus=pcie.1,addr=00.1
        -device vfio-pci,host=03:00.2,bus=pcie.1,addr=00.2
        -device vfio-pci,host=03:00.3,bus=pcie.1,addr=00.3
        -device usb-host,vendorid=0x04B4,productid=0x0510 # keyboard
        -device usb-host,vendorid=0x046D,productid=0xC092 # mouse
        -device usb-host,vendorid=0x8087,productid=0x0a2b # bluetooth
        -device usb-host,vendorid=0x3142,productid=0x0068 # microphone
    )
else
    args+=(-smp 4,cores=4 -m 8G)
fi

# Don't apply new shell settings to the cleanup hook.
(
    # Print the QEMU command before executing it.
    set -x
    # The QEMU container image must already exist.
    /usr/libexec/qemu-kvm "${args[@]}" "$@"
)
