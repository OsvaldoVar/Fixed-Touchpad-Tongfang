#!/usr/bin/env bash
# ==============================================================================
# Herramienta de Automatización ACPI - Touchpad I2C (Chasis Tongfang / Thunderobot)
# Ejecución recomendada: bash thunderobot_acpi_fix.sh
# ==============================================================================

set -e # Detener el script si ocurre cualquier error crítico

# Colores para la terminal
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}[+] Iniciando Protocolo de Parcheo ACPI para Touchpad I2C${NC}"

# 1. Validación de Privilegios y Entorno
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[!] Error: Este script requiere acceso directo al hardware. Ejecútalo con sudo.${NC}"
  exit 1
fi

if ! command -v iasl &> /dev/null || ! command -v cpio &> /dev/null; then
    echo -e "${RED}[!] Error: Faltan dependencias.${NC}"
    echo -e "Instálalas primero según tu distribución (ej. pacman -S acpica cpio / apt install acpica-tools cpio)"
    exit 1
fi

# 2. Extracción y Preparación del Entorno
WORK_DIR="/tmp/acpi_patch_workspace"
echo -e "${YELLOW}[*] Limpiando espacio de trabajo en ${WORK_DIR}...${NC}"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

echo -e "${YELLOW}[*] Extrayendo firmware DSDT de la memoria RAM...${NC}"
cat /sys/firmware/acpi/tables/DSDT > dsdt.dat

echo -e "${YELLOW}[*] Descompilando el binario AML a código fuente ASL...${NC}"
iasl -d dsdt.dat > /dev/null

# 3. Intervención Manual Asistida
echo -e "${GREEN}[+] Código extraído con éxito.${NC}"
echo -e "================================================================="
echo -e "Es hora de la cirugía. El script abrirá el código en 'nano'."
echo -e "Busca 'Device (TPD0)' (Ctrl + W) y aplica las dos correcciones:"
echo -e "  1. Cambia '\"NULL\"' por '\"\\\\_SB.PC00.I2C0\"'"
echo -e "  2. Cambia el Method (_CRS) por: Return (ConcatenateResTemplate (SBFB, SBFG))"
echo -e "Guarda (Ctrl+O, Enter) y sal (Ctrl+X) para continuar la compilación."
echo -e "================================================================="
read -p "Presiona [ENTER] para abrir el editor..."

nano dsdt.dsl

# 4. Compilación y Control de Errores
echo -e "${YELLOW}[*] Recompilando el código modificado...${NC}"
if ! iasl -ve -tc dsdt.dsl; then
    echo -e "${RED}[!] Error de compilación detectado (Probablemente falta una llave '}').${NC}"
    echo -e "Revisa el log arriba. Abortando el script por seguridad del kernel."
    exit 1
fi

# 5. Forjado del Initrd
echo -e "${YELLOW}[*] Forjando la imagen CPIO para la inyección del kernel...${NC}"
mkdir -p kernel/firmware/acpi
cp dsdt.aml kernel/firmware/acpi/
find kernel | cpio -H newc -o > acpi_override.img 2>/dev/null

# 6. Despliegue en partición de arranque
BOOT_DIR="/boot"
if [ -d "/efi" ]; then
    BOOT_DIR="/efi"
elif [ -d "/boot/efi" ]; then
    BOOT_DIR="/boot/efi"
fi

echo -e "${YELLOW}[*] Copiando la imagen maestra a ${BOOT_DIR}...${NC}"
cp acpi_override.img "${BOOT_DIR}/"

# 7. Automatización de Sincronización (Race Condition Systemd)
SERVICE_PATH="/etc/systemd/system/touchpad-fix.service"
echo -e "${YELLOW}[*] Generando servicio de reinicio en caliente para el driver i2c_hid_acpi...${NC}"

cat << 'EOF' > "$SERVICE_PATH"
[Unit]
Description=Solucionar asincronia del Touchpad Thunderobot
After=systemd-modules-load.service

[Service]
Type=oneshot
ExecStartPre=/usr/bin/sleep 2
ExecStart=/bin/sh -c 'echo "i2c-36B6C003:00" > /sys/bus/i2c/drivers/i2c_hid_acpi/unbind 2>/dev/null; echo "i2c-36B6C003:00" > /sys/bus/i2c/drivers/i2c_hid_acpi/bind'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

echo -e "${YELLOW}[*] Recargando el demonio de Systemd y habilitando el servicio...${NC}"
systemctl daemon-reload
systemctl enable touchpad-fix.service > /dev/null 2>&1

# 8. Cierre y Veredicto
echo -e "================================================================="
echo -e "${GREEN}[+] ¡AUTOMATIZACIÓN COMPLETADA CON ÉXITO!${NC}"
echo -e "El parche ACPI está forjado en: ${BOOT_DIR}/acpi_override.img"
echo -e "El servicio systemd está instalado y activado."
echo -e ""
echo -e "${YELLOW}PASO FINAL MANUAL REQUERIDO:${NC}"
echo -e "El script no modificó tu Bootloader (Grub/Systemd-boot) por seguridad."
echo -e "Asegúrate de declarar 'initrd /acpi_override.img' en tu configuración"
echo -e "de arranque para que se cargue antes de tu initramfs principal."
echo -e "================================================================="
