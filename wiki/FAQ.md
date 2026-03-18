# FAQ — Preguntas frecuentes

## ¿Por qué el script no hace nada cuando lo ejecuto sin argumentos?

El comportamiento por defecto es **Plan** (análisis sin cambios). Esto es intencional: primero revisas qué haría el script y luego decides aplicarlo con `-Mode Apply`.

---

## ¿Qué pasa si ejecuto Apply sin haber visto el Plan antes?

El modo Apply hace exactamente lo mismo que Plan más la ejecución de las acciones `AUTO`. No es necesario ejecutar Plan primero; Apply también muestra toda la salida antes de actuar.

---

## El script dice "Access denied" o falla silenciosamente en algunos módulos

Asegúrate de ejecutar PowerShell **como Administrador**. El script requiere privilegios elevados (`#Requires -RunAsAdministrator`). Sin ellos no puede leer algunas claves del Registro ni ejecutar cmdlets del sistema.

---

## ¿Cómo sé qué acciones son AUTO y cuáles son MANUAL?

- Las líneas marcadas con `[+]`, `[-]` sin nota especial son generalmente AUTO.
- Las líneas marcadas con `[?]` son siempre MANUAL.
- El resumen al final indica cuántas acciones AUTO y MANUAL se encontraron.
- En el informe de texto cada acción incluye su tipo.

---

## ¿Es seguro ejecutar el modo Apply sin revisar?

Las acciones AUTO están diseñadas para ser no destructivas o fácilmente reversibles (vaciar caché, papelera, archivos temporales, deshabilitar entradas de inicio). Sin embargo, siempre es buena práctica ejecutar Plan primero.

Las acciones potencialmente destructivas (como eliminar duplicados) son siempre MANUAL y **nunca** se ejecutan automáticamente.

---

## El módulo File Analysis omite mis carpetas de Descargas

Si tu perfil de usuario está en una unidad distinta a `C:\` (p. ej. `D:\Users\diego`), `Test-OnSystemDrive` devolverá `$false` y la ruta se omitirá con un aviso. Actualmente el módulo solo opera en la unidad del sistema.

---

## ¿Cómo añado un programa a la lista de inicio para que se deshabilite automáticamente?

Edita `$StartupDB` en `scripts/maintenance.ps1` y añade una entrada con `Auto = $true`:

```powershell
"NombreDelPrograma" = @{ Cat = "Gaming"; Auto = $true }
```

El nombre debe coincidir exactamente con la clave en el Registro (`HKCU:\Software\Microsoft\Windows\CurrentVersion\Run`).

---

## ¿Cómo cambio el día y hora de la tarea programada?

Edita las variables al inicio de `scripts/setup.ps1`:

```powershell
$TriggerDay  = "Monday"
$TriggerTime = "08:00"
```

Luego ejecuta `.\setup.ps1` de nuevo como Administrador para actualizar la tarea.

---

## Los informes tienen caracteres extraños

Asegúrate de abrir el archivo con codificación **UTF-8**. Los informes se guardan en UTF-8. En el Bloc de notas de Windows 10/11 esto es automático; en editores más antiguos puede ser necesario seleccionarlo manualmente.

---

## ¿Puedo ejecutar el script en PowerShell 5.1?

Sí, es compatible con PowerShell 5.1 y superior. Se recomienda PowerShell 7+ para mejor compatibilidad con `Get-CimInstance` y soporte completo de UTF-8.

---

## ¿Qué hace `setup.ps1` exactamente?

Registra una tarea en el Programador de tareas de Windows con estas características:

- Se ejecuta cada domingo a las 10:00 (configurable)
- Se ejecuta como SYSTEM con privilegios elevados
- No abre ninguna ventana visible (`-WindowStyle Hidden`)
- Si ya hay una instancia en ejecución, ignora la nueva (`MultipleInstances = IgnoreNew`)
- Ejecuta `maintenance.ps1 -Mode Apply` automáticamente
