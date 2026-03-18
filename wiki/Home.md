# PC Maintenance — Wiki

Bienvenido a la wiki del proyecto **PC Maintenance**.
Este script de PowerShell automatiza el mantenimiento de Windows 11 usando un flujo **Plan / Apply** inspirado en Terraform: primero ves exactamente qué cambiaría, y solo después decides aplicarlo.

---

## Páginas

| Página | Descripción |
|--------|-------------|
| [Inicio rápido](Quick-Start.md) | Instalación y primeras ejecuciones |
| [Arquitectura](Architecture.md) | Cómo están organizados los módulos y el registro de acciones |
| [Módulos](Modules.md) | Qué revisa y qué hace cada módulo |
| [Configuración](Configuration.md) | Todas las opciones de `$Cfg` y el programador de tareas |
| [Añadir un módulo](Adding-a-Module.md) | Guía paso a paso para extender el script |
| [Salida e informes](Output-and-Reports.md) | Cómo leer la salida en consola y los informes de texto |
| [FAQ](FAQ.md) | Preguntas frecuentes y solución de problemas |

---

## Flujo de trabajo resumido

```
.\scripts\maintenance.ps1           # Plan: analiza, no cambia nada
.\scripts\maintenance.ps1 -Mode Apply  # Apply: ejecuta las acciones AUTO
```

> Siempre ejecuta **como Administrador**.
