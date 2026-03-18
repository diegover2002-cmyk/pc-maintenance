# Arquitectura

## Patrón central

Todo el script sigue el mismo patrón de tres fases:

```
Collect-XxxActions()
       │
       ├─► Write-PlanLine()   ← imprime lo que se haría
       └─► Register-Action()  ← añade la acción al registro global
                  │
                  └─► $script:Registry[]
                              │
                        ┌─────┴──────┐
                     Plan mode    Apply mode
                     (solo lee)  (ejecuta AUTO)
```

1. **Collect** — cada módulo analiza el sistema y llama a `Register-Action` y `Write-PlanLine`.
2. **Registry** — lista global `$script:Registry` que acumula todas las acciones propuestas.
3. **Plan** — recorre el registro e imprime un resumen. Sin cambios.
4. **Apply** — recorre el registro y ejecuta el `-Run` scriptblock de cada acción `AUTO`.

---

## Tipos de acción

| Tipo | Descripción |
|------|-------------|
| `AUTO` | Segura para ejecutar automáticamente en modo Apply |
| `MANUAL` | Se imprime como recordatorio; nunca se ejecuta automáticamente |

---

## Funciones clave

### `Register-Action`

```powershell
Register-Action -Module "Cleanup" -Type "AUTO" -Label "Vaciar Papelera" -Run { Clear-RecycleBin -Force }
```

Parámetros:

| Parámetro | Tipo | Descripción |
|-----------|------|-------------|
| `-Module` | string | Nombre del módulo que registra la acción |
| `-Label` | string | Texto legible de la acción |
| `-Type` | `AUTO` / `MANUAL` | Cómo se trata en Apply |
| `-Detail` | string | Información adicional (opcional) |
| `-Bytes` | long | Espacio liberado estimado (opcional, para el resumen) |
| `-Run` | scriptblock | Código a ejecutar (solo `AUTO`) |

### `Write-PlanLine`

```powershell
Write-PlanLine "Se añadirá X"          "ADD"
Write-PlanLine "Se eliminará Y"        "DEL"
Write-PlanLine "Atención: disco lleno" "WARN"
Write-PlanLine "Firewall activo"       "KEEP"
Write-PlanLine "Revisar driver Z"      "MANUAL"
Write-PlanLine "3 archivos analizados" "INFO"
```

Prefijos y colores en consola:

| Tipo | Símbolo | Color |
|------|---------|-------|
| `ADD` | `+` | Verde |
| `DEL` | `-` | Amarillo |
| `WARN` | `!` | Rojo |
| `KEEP` | `=` | Gris oscuro |
| `MANUAL` | `?` | Magenta |
| `INFO` | ` ` | Cian |

### `Show-Section`

```powershell
Show-Section "SECURITY"
```

Imprime una cabecera de sección formateada en consola y en el log.

### `Format-Bytes`

```powershell
Format-Bytes 1073741824   # → "1.0 GB"
```

### `ConvertTo-AsciiSafe`

Elimina caracteres no-ASCII de una cadena antes de escribirla en el log.
Evita errores de codificación en rutas o nombres con caracteres especiales.

### `Test-OnSystemDrive`

```powershell
Test-OnSystemDrive "D:\Downloads"   # → $false (no está en C:\)
```

Valida que una ruta esté en la unidad del sistema (`$env:SystemDrive`).
Los módulos File Analysis y Documents omiten las rutas que devuelven `$false`.

---

## Archivos del proyecto

```
pc-maintenance/
├── .github/
│   └── workflows/        ← CI/CD: release, test, validate
├── scripts/
│   ├── maintenance.ps1   ← script principal (todos los módulos)
│   └── setup.ps1         ← registra la tarea en el Programador
├── logs/                 ← creado automáticamente, ignorado por git
├── reports/              ← creado automáticamente, ignorado por git
├── wiki/                 ← esta documentación
├── CHANGELOG.md
└── README.md
```

---

## Flujo completo en modo Apply

```
main()
 ├── Collect-SecurityActions
 ├── Collect-CleanupActions
 ├── Collect-StartupActions
 ├── Collect-FileAnalysisActions
 ├── Collect-DiskActions
 ├── Collect-DocumentsActions
 ├── Collect-DriversActions
 ├── Collect-BackupActions
 ├── Collect-NetworkActions
 ├── Collect-TemperatureActions
 └── Collect-ProcessActions
          │
          ▼
   $script:Registry (lista de acciones)
          │
    ┌─────┴──────────┐
    │ Imprimir resumen│
    │ Plan / Apply    │
    └─────────────────┘
          │
    (Apply) foreach AUTO → .Run.Invoke()
          │
    Guardar informe .txt
```
