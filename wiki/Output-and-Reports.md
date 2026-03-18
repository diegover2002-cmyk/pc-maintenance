# Salida e informes

## Salida en consola

La salida usa prefijos de color al estilo Terraform para identificar el tipo de cada línea de un vistazo:

```
[+] Vaciar Papelera de reciclaje (1.2 GB)
[-] Eliminar 47 archivos temporales (234 MB)
[!] Espacio libre en C: 12.3 GB — por debajo del umbral (15 GB)
[=] Windows Defender: activo y actualizado
[?] MANUAL: Revisar driver con error — Dispositivo USB desconocido
    Estadística: 3 archivos duplicados detectados
```

| Prefijo | Color | Tipo | Significado |
|---------|-------|------|-------------|
| `  + ` | Verde | `ADD` | Acción que añade o habilita algo |
| `  - ` | Amarillo | `DEL` | Acción que elimina algo |
| `  ! ` | Rojo | `WARN` | Advertencia que requiere atención |
| `  = ` | Gris oscuro | `KEEP` | Estado correcto, sin cambios necesarios |
| `  ? ` | Magenta | `MANUAL` | El usuario debe intervenir manualmente |
| `    ` | Cian | `INFO` | Información adicional |

---

## Resumen al final de cada ejecución

Tras recorrer todos los módulos, el script imprime un resumen del registro:

```
══════════════════════════════════════════
  PLAN SUMMARY
══════════════════════════════════════════
  AUTO actions   : 8   (se ejecutarán en Apply)
  MANUAL actions : 3   (requieren intervención humana)
  Total          : 11
══════════════════════════════════════════
```

En modo Apply el resumen cambia a:

```
══════════════════════════════════════════
  APPLY COMPLETE
══════════════════════════════════════════
  Executed : 8
  Skipped  : 0  (MANUAL)
══════════════════════════════════════════
```

---

## Archivos de informe

Después de cada ejecución se generan dos archivos de texto:

### `reports/report_<modo>_<timestamp>.txt`

Copia completa de toda la salida de consola (sin colores ANSI), guardada en la carpeta `reports/` del proyecto.

Ejemplo de nombre: `reports/report_Apply_20260317_103045.txt`

### `Desktop\PC_Maintenance_Report.txt`

El mismo informe copiado al Escritorio para acceso rápido.
Se sobreescribe en cada ejecución.

---

## Archivos de log

Los logs se guardan en `logs/maintenance_<timestamp>.log`.
Los logs más antiguos que `LogRotateDays` (30 días por defecto) se eliminan automáticamente.

---

## Modo silencioso (tarea programada)

Cuando el script se ejecuta desde el Programador de tareas (vía `setup.ps1`), no abre ninguna ventana visible gracias a `-WindowStyle Hidden`. El informe se sigue guardando en `reports/` y en el Escritorio para revisión posterior.
