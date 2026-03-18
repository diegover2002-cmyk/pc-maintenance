# Inicio rápido

## Requisitos

| Requisito | Detalle |
|-----------|---------|
| Sistema operativo | Windows 10 / 11 |
| PowerShell | 5.1 o superior (se recomienda 7+) |
| Permisos | **Ejecutar como Administrador** |
| Dependencias externas | Ninguna — solo cmdlets integrados y WMI/CIM |

---

## 1. Clonar el repositorio

```powershell
git clone https://github.com/diegover2002-cmyk/pc-maintenance.git
cd pc-maintenance
```

---

## 2. Permitir la ejecución de scripts (una sola vez)

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

---

## 3. Registrar la tarea programada semanal (una sola vez)

```powershell
cd scripts
.\setup.ps1
```

Esto registra un trabajo en el Programador de tareas de Windows que se ejecuta cada **domingo a las 10:00** de forma silenciosa como SYSTEM.

---

## 4. Ejecutar el script

### Modo Plan (seguro, sin cambios)

```powershell
.\scripts\maintenance.ps1
```

Analiza el sistema y muestra todo lo que se haría. No modifica nada.

### Modo Apply (ejecuta las acciones AUTO)

```powershell
.\scripts\maintenance.ps1 -Mode Apply
```

Ejecuta todas las acciones marcadas como `AUTO` que el modo Plan encontró.

---

## 5. Leer el informe

Tras cada ejecución se guarda un informe de texto en:

- `reports/report_<modo>_<timestamp>.txt`
- `Desktop\PC_Maintenance_Report.txt` (se sobreescribe cada vez)

Consulta [Salida e informes](Output-and-Reports.md) para interpretar la salida.
