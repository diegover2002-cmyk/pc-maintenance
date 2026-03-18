# Configuración

## Bloque `$Cfg`

Al inicio de `scripts/maintenance.ps1` encontrarás el bloque de configuración principal:

```powershell
$Cfg = @{
    MinFreeGB       = 15
    TempAgeDays     = 7
    LogRotateDays   = 30
    DownloadAgeDays = 60
    DesktopMaxFiles = 20
    LargeFileMB     = 500
    BackupDirs      = @("$env:USERPROFILE\Documents", "$env:USERPROFILE\Desktop")
    DupScanDirs     = @("$env:USERPROFILE\Downloads", "$env:USERPROFILE\Desktop")
}
```

### Referencia de parámetros

| Clave | Tipo | Valor por defecto | Descripción |
|-------|------|:-----------------:|-------------|
| `MinFreeGB` | int | `15` | Umbral de espacio libre (GB). Si una unidad baja de este valor se emite un WARN. |
| `TempAgeDays` | int | `7` | Eliminar archivos temporales más antiguos que N días. |
| `LogRotateDays` | int | `30` | Eliminar logs del proyecto más antiguos que N días. |
| `DownloadAgeDays` | int | `60` | Marcar archivos en Descargas más antiguos que N días. |
| `DesktopMaxFiles` | int | `20` | Avisar si el Escritorio tiene más de N archivos. |
| `LargeFileMB` | int | `500` | Marcar archivos individuales más grandes que N MB. |
| `BackupDirs` | string[] | Documents, Desktop | Directorios que se comprueban para recordatorio de backup. |
| `DupScanDirs` | string[] | Downloads, Desktop | Directorios donde se buscan duplicados por MD5. |

> **Nota:** `DupScanDirs` y `BackupDirs` solo aceptan rutas en la unidad del sistema (`$env:SystemDrive`). Las rutas en otras unidades se omiten con un aviso.

---

## Tarea programada

Edita `scripts/setup.ps1` para cambiar el día y la hora:

```powershell
$TriggerDay  = "Sunday"   # Monday, Tuesday, Wednesday, Thursday, Friday, Saturday, Sunday
$TriggerTime = "10:00"    # formato 24h
```

Después de cambiar estos valores, vuelve a ejecutar `.\setup.ps1` como Administrador para registrar la nueva programación.

La tarea se registra con estas propiedades:

| Propiedad | Valor |
|-----------|-------|
| Nombre | `PCMaintenance` |
| Usuario | SYSTEM |
| Visibilidad | Hidden (sin ventana visible) |
| Instancias simultáneas | IgnoreNew |
| Modo | Apply (ejecuta acciones AUTO automáticamente) |

---

## Base de datos de programas de inicio (`$StartupDB`)

En `maintenance.ps1` existe una tabla hash que clasifica cada entrada de inicio conocida:

```powershell
$StartupDB = @{
    "Steam"   = @{ Cat = "Gaming"; Auto = $true  }
    "Slack"   = @{ Cat = "Work";   Auto = $false }
    # ...
}
```

- `Cat` — categoría del programa (Gaming, Media, Work, System, Security, Browser, Office…)
- `Auto = $true` — el script lo deshabilita automáticamente en modo Apply
- `Auto = $false` — solo se reporta como MANUAL

Para añadir un programa nuevo a la base de datos, agrega una entrada con su nombre exacto tal como aparece en el Registro de Windows.

---

## Patrones de auto-deshabilitación (`$StartupAutoPatterns`)

Lista de patrones wildcard para deshabilitar entradas de inicio cuyo nombre varía (p. ej. identificadores únicos):

```powershell
$StartupAutoPatterns = @(
    "MicrosoftEdgeAutoLaunch_*",
    # añade más patrones aquí
)
```
