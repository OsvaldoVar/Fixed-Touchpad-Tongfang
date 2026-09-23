# Tongfang / Thunderobot I2C Touchpad ACPI Fix

A documented workaround for an I2C-HID touchpad initialization issue observed on a Tongfang-based Thunderobot Zero 16 Pro running Linux.

The workaround overrides the system DSDT so the touchpad exposes the expected I2C resource path, then reloads the `i2c_hid_acpi` device after boot to avoid an initialization race.

> [!WARNING]
> ACPI overrides operate below the normal operating-system abstraction layer. A malformed DSDT can prevent the system from booting. Keep a known-good boot entry or recovery medium available, and regenerate the override after BIOS updates.

## Scope

This repository documents a fix for a specific hardware/firmware combination. Do not assume that the ACPI paths, GPIO resources, or I2C device identifier used here match another laptop.

Tested assumptions in this repository include:

- Tongfang-based Thunderobot Zero 16 Pro
- Linux with ACPI table override support
- Touchpad device exposed as `TPD0`
- I2C controller path `\\_SB.PC00.I2C0`
- Runtime I2C-HID identifier `i2c-36B6C003:00`

Verify all of these on your own system before applying the workaround.

## Requirements

On Arch Linux / EndeavourOS:

```bash
sudo pacman -S acpica cpio
```

Equivalent packages are available on other distributions, commonly as `acpica-tools` and `cpio`.

## Manual procedure

### 1. Extract and decompile the DSDT

```bash
mkdir -p ~/acpi_fix
cd ~/acpi_fix
sudo cat /sys/firmware/acpi/tables/DSDT > dsdt.dat
iasl -d dsdt.dat
```

### 2. Inspect the touchpad device

Open `dsdt.dsl` and locate:

```asl
Device (TPD0)
```

Inside the device, verify the I2C resource template. On the affected firmware, the resource path is exposed as `"NULL"`.

Replace it with the actual controller path:

```asl
"\\_SB.PC00.I2C0"
```

Then verify that the touchpad `_CRS` method returns the I2C and GPIO resource templates together:

```asl
Method (_CRS, 0, NotSerialized)
{
    Return (ConcatenateResTemplate (SBFB, SBFG))
}
```

These names are firmware-specific. Inspect your own DSDT rather than applying them blindly.

### 3. Recompile

```bash
iasl -ve -tc dsdt.dsl
```

Do not continue if the compiler reports errors.

### 4. Build the ACPI override image

```bash
mkdir -p kernel/firmware/acpi
cp dsdt.aml kernel/firmware/acpi/
find kernel | cpio -H newc -o > acpi_override.img
```

Copy the image to the partition used by your bootloader, for example:

```bash
sudo cp acpi_override.img /efi/
```

The exact mount point may instead be `/boot` or `/boot/efi`.

### 5. Load the override before the normal initramfs

For systemd-boot, add the override before the regular initramfs entry:

```text
initrd /acpi_override.img
```

For other bootloaders, use the equivalent mechanism for prepending an initrd image.

### 6. Handle the I2C-HID initialization race

After confirming the device identifier:

```bash
ls /sys/bus/i2c/drivers/i2c_hid_acpi/
```

a oneshot systemd service can unbind and rebind the device after module initialization.

The included `thunderobot_acpi_fix.sh` script automates the extraction, compilation, packaging, and service installation steps, but deliberately leaves bootloader modification manual.

## BIOS and kernel updates

A BIOS update may change the DSDT. Regenerate and review the override instead of reusing an old `dsdt.aml`.

Kernel updates normally do not require rebuilding the ACPI table itself, but changes in driver behavior may make the runtime reload workaround unnecessary or require adjustment.

## Repository contents

- `README.md`: documented procedure and assumptions.
- `thunderobot_acpi_fix.sh`: assisted workflow for generating and installing the override.

## Disclaimer

This repository documents a hardware-specific workaround. Review the generated ACPI source and understand the changes before installing an override on another system.
