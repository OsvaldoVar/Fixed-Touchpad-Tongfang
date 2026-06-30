# Fixed-Touchpad-Tongfang
Esta es la decisión de un verdadero ingeniero de software, colega. La memoria falla, pero la documentación es eterna.

Lo que hicimos hoy no está en ningún foro ni en la wiki de Arch. Fue ingeniería inversa pura sobre el firmware de Tongfang para un chasis con un Intel i9 de 14va generación. A continuación, tienes **El Códice Definitivo**, estructurado de principio a fin, para que puedas replicar esta hazaña en cualquier distribución de Linux (ya sea que reinstales EndeavourOS, regreses a Debian, o apliques tus dotfiles en NixOS).

Guarda este texto como oro.

---

## 🛠️ Fase 1: Preparativos y Extracción (El Quirófano)

Antes de operar, necesitas las herramientas para extraer y desensamblar el código ACPI de la placa base, además de crear el paquete de inyección.

**1. Instala las dependencias:**
En EndeavourOS/Arch, necesitas las herramientas de compilación de Intel y el gestor de archivos comprimidos.

```bash
sudo pacman -S acpica cpio

```

*(Si en el futuro usas NixOS, los paquetes equivalentes son `acpica-tools` y `cpio`).*

**2. Extrae la tabla DSDT original de la BIOS:**
Crea un directorio de trabajo seguro y vuelca el firmware actual.

```bash
mkdir ~/acpi_fix && cd ~/acpi_fix
sudo cat /sys/firmware/acpi/tables/DSDT > dsdt.dat

```

**3. Descompila a código legible (ASL):**

```bash
iasl -d dsdt.dat

```

Esto generará el archivo `dsdt.dsl`. Este es el código fuente de tu placa base.

---

## 🔬 Fase 2: La Cirugía de Código (Resolviendo el laberinto de Tongfang)

Abre el archivo descompilado con tu editor de texto favorito:

```bash
nano dsdt.dsl

```

Presiona `Ctrl + W` y busca el dispositivo principal del touchpad: **`Device (TPD0)`**.

### Corrección 1: Construir el puente I2C

Dentro de `TPD0`, busca el bloque `Name (SBFB, ResourceTemplate ()`. La BIOS de Tongfang lo deja flotando con un parámetro `"NULL"`, lo que provoca que el kernel nunca cree el enlace físico.
**Cambia el `"NULL"` por la ruta real de tu controlador I2C (`"\\_SB.PC00.I2C0"`):**

**Antes:**

```asl
AddressingMode7Bit, "NULL",

```

**Después:**

```asl
AddressingMode7Bit, "\\_SB.PC00.I2C0",

```

### Corrección 2: La Conexión Maestra (El Pin Secreto)

Tongfang esconde el pin GPIO de interrupción. No lo escribe directamente, sino que una función matemática oculta (`GNUM`) lo calcula al arrancar y lo inyecta en la variable **`SBFG`**. Sin embargo, la BIOS le entrega por error a Linux una variable rota llamada `SBFI`.
Baja hasta el **`Method (_CRS, 0, NotSerialized)`** de tu touchpad.
**Bórralo y reemplázalo exactamente por esto para conectar el bus I2C con la variable calculada por la BIOS:**

```asl
            Method (_CRS, 0, NotSerialized)  // _CRS: Current Resource Settings
            {
                Return (ConcatenateResTemplate (SBFB, SBFG))
            }

```

### Corrección 3: Balanceo de Llaves

Asegúrate de que no borraste ninguna llave de cierre por accidente al editar. Justo debajo del bloque de código anterior, debe haber **una llave de cierre `}` cerrando el `Device (TPD0)**` antes de que comience el siguiente dispositivo (que usualmente es `Device (TPL1)`).

Guarda los cambios y sal del editor.

---

## 📦 Fase 3: Compilación y Empaquetado

Ahora debes recompilar las 130,000 líneas de código y empaquetarlas en una imagen CPIO que el kernel de Linux pueda tragar antes de iniciar el sistema operativo.

**1. Compila el código editado:**

```bash
cd ~/acpi_fix
iasl -ve -tc dsdt.dsl

```

*(Debe devolver `0 Errors`. Si da un error de `Premature End-Of-File`, te comiste una llave de cierre `}` en el paso anterior).*

**2. Crea la estructura de carpetas estricta:**
El kernel exige que el archivo se llame `dsdt.aml` y esté en una ruta específica dentro del empaquetado.

```bash
mkdir -p kernel/firmware/acpi
cp dsdt.aml kernel/firmware/acpi/

```

**3. Forja el archivo de inyección (Initrd):**

```bash
find kernel | cpio -H newc -o > acpi_override.img

```

---

## ⚡ Fase 4: La Inyección en el Gestor de Arranque

El archivo `acpi_override.img` contiene tu parche. Necesitas colocarlo en tu partición EFI y decirle a tu gestor de arranque que lo cargue **antes** que la imagen normal del kernel (`initramfs`).

**1. Copia la imagen al EFI:**

```bash
sudo cp acpi_override.img /efi/ 
# (Nota: La ruta puede ser /boot/ o /boot/efi/ dependiendo de cómo montes la partición en el futuro).

```

**2. Configura tu Bootloader:**

* **Si usas systemd-boot:** Ve a `/efi/loader/entries/` y edita la entrada de tu sistema operativo. Añade la línea `initrd /acpi_override.img` **arriba** del `initrd` principal.
* **Si usas GRUB:** Las distribuciones modernas suelen cargar automáticamente archivos llamados `acpi_override` si están en `/boot`. Si no, puedes integrarlo editando `/etc/grub.d/10_linux` o agregando el parámetro initrd manualmente.
* **Si usas NixOS:** Simplemente declara en tu `configuration.nix`:
`boot.initrd.prepend = [ "${/ruta/a/tu/acpi_override.img}" ];`

---

## ⏱️ Fase 5: El Módulo de Poder y la Sincronización (Race Condition)

El parche ACPI le dice a Linux *dónde* está el hardware, pero el cristal sigue apagado eléctricamente. Para darle energía, necesitas el módulo `tuxedo_keyboard`.
Instálalo desde el AUR o el gestor de paquetes de tu distro.

**El Problema del Timeout:**
El driver del touchpad (`i2c_hid_acpi`) es rapidísimo y se lanza en el segundo 7 del arranque. Si `tuxedo_keyboard` no le ha dado energía al cristal en ese milisegundo exacto, el driver sufre un *timeout* y abandona.
Para evitar que el cursor esté muerto al iniciar sesión, automatiza un **reinicio en caliente del driver** con `systemd`.

**1. Crea el servicio:**

```bash
sudo nano /etc/systemd/system/touchpad-fix.service

```

**2. Inyecta este script:**
Esto espera a que la placa base se estabilice (2 segundos) y luego desconecta y reconecta el driver a la fuerza.

```ini
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

```

*(Nota importante: Si en el futuro cambias de laptop, el identificador `i2c-36B6C003:00` podría cambiar. Puedes verificar el tuyo ejecutando `ls /sys/bus/i2c/drivers/i2c_hid_acpi/` una vez que el parche ACPI esté aplicado).*

**3. Activa el guardián:**

```bash
sudo systemctl daemon-reload
sudo systemctl enable touchpad-fix.service

```

---

### Consideraciones Finales

* **Actualizaciones de BIOS:** Si Tongfang o Thunderobot lanzan una actualización de BIOS, la tabla DSDT original cambiará. **Tendrás que repetir este proceso desde la Fase 1**, extrayendo la nueva tabla y parcheándola de nuevo. Nunca reutilices un archivo `dsdt.aml` viejo con una BIOS nueva, o podrías causar un kernel panic.
* **Actualizaciones de Kernel:** La imagen `acpi_override.img` sobrevive a las actualizaciones del kernel de Linux sin problemas. Solo preocúpate si flasheas la placa madre.

Guarda este manual en tu nube personal o en tu repositorio de GitHub, Osvaldo. Con esto en tu arsenal, esa Thunderobot Zero 16 Pro te obedecerá a nivel de hardware, sin importar qué distribución decidas instalarle mañana.
