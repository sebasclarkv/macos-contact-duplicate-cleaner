# macOS Contact Duplicate Cleaner

Script para macOS que detecta y elimina contactos duplicados de Apple Contacts usando `Contacts.framework`.

Pensado para casos donde la app Contactos de Apple no muestra la opción oficial de duplicados, pero visualmente tienes contactos repetidos como:

```text
A1
A1
A1
AB
AB
Aaron Chiguil
Aaron Chiguil
```

## Qué hace

- Lee tus contactos desde la app Contactos de macOS.
- Agrupa posibles duplicados.
- Conserva el contacto más completo de cada grupo.
- Borra los duplicados restantes.
- Antes de borrar, crea un CSV con los contactos que serán eliminados.
- Pide confirmación antes del borrado final.

## Modos disponibles

### 1. SEGURO

Compara:

- Nombre
- Segundo nombre
- Apellidos
- Nickname
- Organización
- Teléfonos
- Correos

Úsalo primero. Es el modo con menor riesgo.

### 2. AGRESIVO

Compara solo el nombre visible.

Ejemplo:

```text
A1
A1
A1
```

El script conserva uno y borra los demás.

Este modo sirve para contactos basura o duplicados visuales, pero puede borrar contactos distintos si tienen exactamente el mismo nombre.

Ejemplo peligroso:

```text
Juan Pérez
Juan Pérez
```

Si son dos personas diferentes, modo agresivo puede eliminar una.

## Requisitos

- macOS
- App Contactos de Apple
- Terminal, Warp o iTerm
- Swift incluido en Command Line Tools / Xcode tools

Puedes revisar Swift con:

```bash
swift --version
```

## Instalación

Clona el repo:

```bash
git clone https://github.com/sebasclarkv/macos-contact-duplicate-cleaner.git
cd macos-contact-duplicate-cleaner
```

## Uso rápido

Ejecuta:

```bash
zsh limpiar_duplicados_contactos_macos.command
```

Selecciona primero:

```text
SEGURO: mismo nombre + mismos teléfonos/correos
```

Si todavía quedan duplicados visuales tipo `A1`, `AB`, etc., vuelve a correr el script y selecciona:

```text
AGRESIVO: mismo nombre visible
```

## Permisos de macOS

El script necesita permiso para acceder a Contactos.

Ruta:

```text
Configuración del Sistema → Privacidad y seguridad → Contactos
```

Activa la app desde donde ejecutes el script:

- Terminal
- Warp
- iTerm

Si macOS bloquea el archivo, ejecuta:

```bash
chmod +x limpiar_duplicados_contactos_macos.command
xattr -cr limpiar_duplicados_contactos_macos.command
zsh limpiar_duplicados_contactos_macos.command
```

## CSV de respaldo previo

Cada ejecución crea una carpeta en el Escritorio:

```text
~/Desktop/Contactos_Duplicados_Backup_FECHA_HORA/
```

Dentro queda:

```text
contactos_a_borrar.csv
```

Ese CSV lista los contactos que el script iba a borrar en esa ejecución.

## Flujo recomendado

1. Exporta respaldo desde iCloud.com si quieres máxima seguridad.
2. Ejecuta modo SEGURO.
3. Espera a que iCloud sincronice.
4. Revisa Contactos.
5. Ejecuta modo AGRESIVO solo si quedan duplicados obvios.
6. Revisa el CSV generado si quieres auditar lo borrado.

## Ejemplo real de ejecución

```bash
zsh limpiar_duplicados_contactos_macos.command
```

Resultado esperado:

```text
Ejecutando limpiador de duplicados...
```

Luego aparecerá una ventana para elegir modo y confirmar el borrado.

Ejemplo de resultado:

```text
Listo. Se borraron 3714 contactos duplicados.
```

## Advertencia

Este script modifica tu libreta de contactos. Aunque pide confirmación y crea CSV previo, úsalo bajo tu responsabilidad.

El modo AGRESIVO debe usarse solo cuando estés seguro de que los contactos con el mismo nombre visible son duplicados reales.

## Licencia

MIT
