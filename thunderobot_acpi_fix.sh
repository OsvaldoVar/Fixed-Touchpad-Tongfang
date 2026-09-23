#!/usr/bin/env bash
# Assisted ACPI override workflow for a Tongfang / Thunderobot I2C touchpad.
# This script preserves the original hardware-specific procedure documented
# in README.md and intentionally does not modify the bootloader.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}[+] Starting ACPI touchpad override workflow${NC}"

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[!] This script requires root privileges. Run it with sudo.${NC}"
  exit 1
fi

if ! command -v iasl &> /dev/null || ! command -v cpio &> /dev/null; then
  echo -e "${RED}[!] Missing required dependencies: iasl and/or cpio.${NC}"
  echo "Arch/EndeavourOS: pacman -S acpica cpio"
  echo "Debian/Ubuntu:    apt install acpica-tools cpio"
  exit 1
fi

WORK_DIR="/tmp/acpi_patch_workspace"
echo -e "${YELLOW}[*] Preparing workspace: ${WORK_DIR}${NC}"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

echo -e "${YELLOW}[*] Extracting system DSDT${NC}"
cat /sys/firmware/acpi/tables/DSDT > dsdt.dat

echo -e "${YELLOW}[*] Decompiling DSDT${NC}"
iasl -d dsdt.dat > /dev/null

echo
echo "Manual review required."
echo "Locate Device (TPD0) in dsdt.dsl and verify the hardware-specific changes"
echo "documented in README.md:"
echo '  1. Replace the affected I2C resource path "NULL" with "\\_SB.PC00.I2C0".'
echo "  2. Verify _CRS returns ConcatenateResTemplate (SBFB, SBFG)."
echo
read -r -p "Press ENTER to open dsdt.dsl in nano..."

nano dsdt.dsl

echo -e "${YELLOW}[*] Recompiling modified DSDT${NC}"
if ! iasl -ve -tc dsdt.dsl; then
  echo -e "${RED}[!] DSDT compilation failed. No override will be installed.${NC}"
  exit 1
fi

echo -e "${YELLOW}[*] Building ACPI override image${NC}"
mkdir -p kernel/firmware/acpi
cp dsdt.aml kernel/firmware/acpi/
find kernel | cpio -H newc -o > acpi_override.img 2>/dev/null

BOOT_DIR="/boot"
if [ -d "/efi" ]; then
  BOOT_DIR="/efi"
elif [ -d "/boot/efi" ]; then
  BOOT_DIR="/boot/efi"
fi

echo -e "${YELLOW}[*] Copying override image to ${BOOT_DIR}${NC}"
cp acpi_override.img "${BOOT_DIR}/"

SERVICE_PATH="/etc/systemd/system/touchpad-fix.service"
echo -e "${YELLOW}[*] Installing i2c_hid_acpi reload service${NC}"

cat << 'EOF' > "$SERVICE_PATH"
[Unit]
Description=Reload Thunderobot I2C-HID touchpad after module initialization
After=systemd-modules-load.service

[Service]
Type=oneshot
ExecStartPre=/usr/bin/sleep 2
ExecStart=/bin/sh -c 'echo "i2c-36B6C003:00" > /sys/bus/i2c/drivers/i2c_hid_acpi/unbind 2>/dev/null; echo "i2c-36B6C003:00" > /sys/bus/i2c/drivers/i2c_hid_acpi/bind'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable touchpad-fix.service > /dev/null 2>&1

echo
echo -e "${GREEN}[+] ACPI override image created and service installed.${NC}"
echo "Override image: ${BOOT_DIR}/acpi_override.img"
echo
echo -e "${YELLOW}Manual step required:${NC}"
echo "Configure your bootloader to load acpi_override.img before the regular initramfs."
echo "See README.md for the procedure and hardware-specific assumptions."
