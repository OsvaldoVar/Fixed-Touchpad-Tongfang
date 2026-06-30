Aquí tienes la tercera versión. Estrictamente técnica, directa y estructurada como documentación de sistemas. Describe con precisión la causa técnica y el efecto de cada instrucción.

---

### **Documentación de Intervención: Sobrescritura ACPI DSDT para Controlador I2C HID**

**Objetivo del Parche:** Modificar la tabla DSDT en tiempo de arranque para corregir el enrutamiento nulo del bus I2C en chasis Tongfang y obligar al método `_CRS` a leer el pin de interrupción dinámica (GPIO) generado por la BIOS. Incluye la mitigación de la condición de carrera en el arranque para el módulo `i2c_hid_acpi`.

---

#### **Fase 1: Volcado y Descompilación de Firmware**

*Propósito: Extraer la configuración de hardware almacenada en la RAM y convertir el binario AML a texto legible ASL.*

1. **Instalar dependencias de compilación y empaquetado:**
```bash
sudo pacman -S acpica cpio

```


2. **Extraer la tabla maestra (DSDT):**
```bash
mkdir ~/acpi_fix && cd ~/acpi_fix
sudo cat /sys/firmware/acpi/tables/DSDT > dsdt.dat

```


3. **Descompilar el binario:**
```bash
iasl -d dsdt.dat

```


*(Salida: `dsdt.dsl`, archivo de código fuente editable).*

---

#### **Fase 2: Modificación de Variables de Enrutamiento (ASL)**

*Propósito: Reasignar rutas lógicas rotas hacia el hardware físico.*

1. **Editar el archivo fuente:**
```bash
nano dsdt.dsl

```


2. **Declaración del Bus I2C (Dispositivo TPD0):**
* **Acción:** Buscar la cadena `Device (TPD0)` y localizar el bloque de configuración `Name (SBFB...)`.
* **Corrección:** Sustituir el parámetro `"NULL"` por la ruta absoluta del controlador en la placa base: `"\\_SB.PC00.I2C0"`.
* **Efecto:** Permite al kernel construir el enlace `physical_node` necesario para la carga inicial del driver.


3. **Asignación del Método de Recursos (`_CRS`):**
* **Acción:** Dentro del mismo `TPD0`, ubicar `Method (_CRS, 0, NotSerialized)`.
* **Corrección:** Reemplazar el bloque de código completo por la concatenación de la definición del bus (`SBFB`) y la variable nativa de interrupción de Tongfang (`SBFG`).
* **Código exacto:**
```asl
Method (_CRS, 0, NotSerialized)  // _CRS: Current Resource Settings
{
    Return (ConcatenateResTemplate (SBFB, SBFG))
}

```


* **Efecto:** Anula la asignación estática rota e instruye a Linux a leer el pin GPIO que la BIOS genera dinámicamente al momento del arranque.


4. **Verificación Estructural:**
Asegurar que la llave `}` que cierra el bloque `Device (TPD0)` siga presente inmediatamente después del método `_CRS` recién editado para evitar el error de compilación 6126 (sintaxis desbalanceada).

---

#### **Fase 3: Recompilación y Creación de Initrd**

*Propósito: Generar un archivo de imagen que el kernel pueda montar y priorizar sobre las tablas ACPI originales.*

1. **Compilar el código parcheado:**
```bash
cd ~/acpi_fix
iasl -ve -tc dsdt.dsl

```


*(Resultado esperado: 0 Errores).*
2. **Forjar el archivo de inyección (Initrd):**
```bash
mkdir -p kernel/firmware/acpi
cp dsdt.aml kernel/firmware/acpi/
find kernel | cpio -H newc -o > acpi_override.img

```



---

#### **Fase 4: Configuración del Gestor de Arranque**

*Propósito: Inyectar el parche antes del arranque del entorno del sistema operativo.*

1. **Montar la imagen en la partición EFI:**
```bash
sudo cp acpi_override.img /efi/

```


2. **Declaración Temprana (Ejemplo para systemd-boot):**
* Abrir la entrada principal de inicio (ej. `/efi/loader/entries/endeavouros.conf`).
* Insertar `initrd /acpi_override.img` en la primera línea disponible de inicialización, estrictamente **arriba** de la imagen `initramfs` estándar.



---

#### **Fase 5: Mitigación de Condición de Carrera (Driver Sync)**

*Propósito: Retrasar la conexión del driver hasta que el Controlador Embebido (EC) envíe voltaje al cristal, evitando un fallo por timeout (1000ms) durante la secuencia de arranque.*

1. **Crear script de ejecución en Systemd:**
```bash
sudo nano /etc/systemd/system/touchpad-fix.service

```


2. **Definir la regla de desenganche/enganche:**
```ini
[Unit]
Description=Reinicio forzado driver I2C Touchpad
After=systemd-modules-load.service

[Service]
Type=oneshot
ExecStartPre=/usr/bin/sleep 2
ExecStart=/bin/sh -c 'echo "i2c-36B6C003:00" > /sys/bus/i2c/drivers/i2c_hid_acpi/unbind 2>/dev/null; echo "i2c-36B6C003:00" > /sys/bus/i2c/drivers/i2c_hid_acpi/bind'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target

```


3. **Habilitar el disparador:**
```bash
sudo systemctl daemon-reload
sudo systemctl enable touchpad-fix.service

```



**Nota de dependencia:** Este procedimiento está acoplado al hash generado por la versión actual de la BIOS. Si el firmware de la placa base sufre una actualización por parte del fabricante, el archivo `acpi_override.img` actual desencadenará un pánico del kernel y el procedimiento deberá repetirse desde la Fase 1.
