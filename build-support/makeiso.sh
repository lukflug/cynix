#!/bin/sh

set -e

script_dir="$(dirname "$0")"
test -z "${script_dir}" && script_dir=.

source_dir="$(cd "${script_dir}"/.. && pwd -P)"
build_dir="$(pwd -P)"

# Set ARCH based on the build directory.
case "$(basename "${build_dir}")" in
    build-x86_64) ARCH=x86_64 ;;
    *)
        echo "error: The build directory must be called 'build-<architecture>'." 1>&2
        exit 1
        ;;
esac

# Create build directory if needed.
mkdir -p "${build_dir}"

# Enter build directory.
cd "${build_dir}"

# If already initialized, get ARCH from .jinx-parameters file.
if [ -f .jinx-parameters ]; then
    if ! [ "${ARCH}" = "$(. ./.jinx-parameters && echo "${JINX_ARCH}")" ]; then
        echo "error: Jinx architecture and build dir derived architecture mismatch. Delete build dir." 1>&2
        exit 1
    fi
fi

# Build the sysroot with jinx, and make sure the packages the particular
# target needs.
set -f
rm -rf sysroot

if ! [ -f .jinx-parameters ]; then
    "${source_dir}"/jinx init "${source_dir}" ARCH="${ARCH}"
fi

"${source_dir}"/jinx build-if-needed base $PKGS_TO_INSTALL

"${source_dir}"/jinx install "sysroot" base $PKGS_TO_INSTALL

set +f

if ! [ -d host-pkgs/limine ]; then
    "${source_dir}"/jinx host-build limine
fi

# Make an initramfs with the sysroot.
( cd sysroot && tar cf ../initramfs.tar * )

# Prepare the iso and boot directories.
rm -rf iso_root
mkdir -pv iso_root/boot
cp sysroot/usr/share/cynix/cynix iso_root/boot/
cp initramfs.tar iso_root/boot/
cp "${source_dir}"/build-support/limine.conf iso_root/boot/

# Install the limine binaries.
cp host-pkgs/limine/usr/local/share/limine/limine-bios.sys iso_root/boot/
cp host-pkgs/limine/usr/local/share/limine/limine-bios-cd.bin iso_root/boot/
cp host-pkgs/limine/usr/local/share/limine/limine-uefi-cd.bin iso_root/boot/
mkdir -pv iso_root/EFI/BOOT
cp host-pkgs/limine/usr/local/share/limine/BOOT*.EFI iso_root/EFI/BOOT/

# Create the disk image.
xorriso -as mkisofs -R -r -J -b boot/limine-bios-cd.bin \
    -no-emul-boot -boot-load-size 4 -boot-info-table -hfsplus \
    -apm-block-size 2048 --efi-boot boot/limine-uefi-cd.bin \
    -efi-boot-part --efi-boot-image --protective-msdos-label \
    iso_root -o cynix.iso

# Install limine.
host-pkgs/limine/usr/local/bin/limine bios-install cynix.iso
