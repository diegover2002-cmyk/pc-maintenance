# Añadir un módulo

Esta guía explica cómo extender el script con un nuevo módulo siguiendo el patrón del proyecto.

---

## Paso 1 — Crear la función `Collect-XxxActions`

Añade tu función en `scripts/maintenance.ps1`, después de los módulos existentes y antes del bloque `$AllModules`.

```powershell
# ============================================================
#  MI MÓDULO
# ============================================================
function Collect-MiModuloActions {
    Show-Section "MI MODULO"

    # 1. Analizar el sistema
    $resultado = Get-AlgunDato

    # 2a. Acción AUTO (segura para ejecutar automáticamente)
    if ($resultado -eq "malo") {
        Write-PlanLine "Corregir X automáticamente" "ADD"
        Register-Action -Module "MiModulo" `
                        -Type   "AUTO" `
                        -Label  "Corregir X" `
                        -Run    { Invoke-Correccion }
    }

    # 2b. Acción MANUAL (solo aviso, nunca auto-ejecutada)
    if ($resultado -eq "sospechoso") {
        Write-PlanLine "Revisar manualmente: Y" "MANUAL"
        Register-Action -Module "MiModulo" `
                        -Type   "MANUAL" `
                        -Label  "Revisar Y" `
                        -Detail "Descripción de qué hay que hacer"
    }

    # 2c. Sin acción necesaria
    if ($resultado -eq "ok") {
        Write-PlanLine "Todo en orden" "KEEP"
    }
}
```

---

## Paso 2 — Usar `Write-PlanLine` correctamente

La función acepta el mensaje como primer argumento y el tipo como segundo:

```powershell
Write-PlanLine "Mensaje aquí" "TIPO"
```

Elige el tipo según lo que comuniques:

| Tipo | Cuándo usarlo |
|------|---------------|
| `ADD` | Se va a añadir o habilitar algo |
| `DEL` | Se va a eliminar algo |
| `WARN` | Situación que requiere atención |
| `KEEP` | Estado correcto, sin cambios |
| `MANUAL` | El usuario debe intervenir manualmente |
| `INFO` | Información adicional (estadísticas, recuentos…) |

---

## Paso 3 — Registrar acciones con `Register-Action`

Para acciones ejecutables en Apply, siempre proporciona el parámetro `-Run`:

```powershell
Register-Action -Module "MiModulo" `
                -Type   "AUTO" `
                -Label  "Descripción legible" `
                -Detail "Información adicional (opcional)" `
                -Bytes  $bytesLiberados `
                -Run    {
                    # Código que se ejecutará en Apply
                }.GetNewClosure()
```

> **Importante:** Cuando registras acciones dentro de un bucle, añade `.GetNewClosure()` al scriptblock para capturar correctamente las variables del iterador. Sin esto, todas las acciones del bucle usarán el valor final de la variable.

```powershell
foreach ($archivo in $archivos) {
    $ruta = $archivo.FullName
    Register-Action -Module "MiModulo" `
                    -Type   "AUTO" `
                    -Label  "Eliminar $ruta" `
                    -Run    { Remove-Item $ruta -Force }.GetNewClosure()
}
```

---

## Paso 4 — Registrar el módulo en `$AllModules`

Localiza el hashtable `$AllModules` en la sección `# MAIN` de `maintenance.ps1` y añade tu módulo:

```powershell
$AllModules = [ordered]@{
    "Security"    = { Collect-SecurityActions    }
    "Cleanup"     = { Collect-CleanupActions     }
    "Startup"     = { Collect-StartupActions     }
    "FileAnalysis"= { Collect-FileAnalysisActions}
    "Disk"        = { Collect-DiskActions        }
    "Documents"   = { Collect-DocumentsActions   }
    "Drivers"     = { Collect-DriversActions     }
    "Backup"      = { Collect-BackupActions      }
    "Network"     = { Collect-NetworkActions     }
    "Temperature" = { Collect-TemperatureActions }
    "Processes"   = { Collect-ProcessActions     }
    "MiModulo"    = { Collect-MiModuloActions    }   # ← añade aquí
}
```

Esto hace que el módulo aparezca automáticamente en el menú interactivo (`-Interactive`) y en la ejecución por defecto.

---

## Paso 5 — Actualizar el README y la wiki

Añade una fila a la tabla de módulos en `README.md`:

```markdown
| 12 | **Mi Módulo** | Descripción breve de lo que hace |
```

Añade también una sección en `wiki/Modules.md` documentando las comprobaciones, umbrales y tipos de acción.

---

## Buenas prácticas

- No lances excepciones: usa `$ErrorActionPreference = "SilentlyContinue"` (ya está activo globalmente).
- Usa `Format-Bytes` para mostrar tamaños de archivo.
- Usa `ConvertTo-AsciiSafe` al escribir rutas o nombres en el log para evitar errores de codificación.
- Usa `Test-OnSystemDrive` si tu módulo accede a rutas del usuario (por si el perfil está en otra unidad).
- Mantén cada módulo autocontenido: no dependas del estado dejado por otro módulo.
