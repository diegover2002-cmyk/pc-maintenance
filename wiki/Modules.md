# Módulos

El script incluye once módulos. Cada uno sigue el patrón `Collect-XxxActions`.

---

## 1. Security

**Función:** `Collect-SecurityActions`

| Comprobación | Acción si falla | Tipo |
|--------------|-----------------|------|
| Windows Defender habilitado | Aviso | MANUAL |
| Protección en tiempo real activa | Aviso | MANUAL |
| Definiciones de Defender < 3 días | Actualizar definiciones | AUTO |
| Actualizaciones de Windows pendientes | Aviso por cada update | MANUAL |
| Perfil de Firewall (Domain/Private/Public) activo | Aviso por perfil desactivado | MANUAL |

---

## 2. Cleanup

**Función:** `Collect-CleanupActions`

| Comprobación | Umbral | Tipo |
|--------------|--------|------|
| Archivos en `%TEMP%` más antiguos que `TempAgeDays` | 7 días | AUTO |
| Archivos en `C:\Windows\Temp` más antiguos que `TempAgeDays` | 7 días | AUTO |
| Archivos en `C:\Windows\Prefetch` más antiguos que 14 días | 14 días | AUTO |
| Papelera de reciclaje no vacía | > 0 elementos | AUTO |
| Caché de Windows Update (`SoftwareDistribution\Download`) | siempre | AUTO |
| Caché de Chrome (`AppData\Local\Google\Chrome\User Data\Default\Cache`) | > 10 MB | AUTO |
| Caché de Edge (`AppData\Local\Microsoft\Edge\User Data\Default\Cache`) | > 10 MB | AUTO |
| Rotación de logs del proyecto | > `LogRotateDays` días | AUTO |

---

## 3. Startup Programs

**Función:** `Collect-StartupActions`

Analiza las entradas del Registro de inicio de Windows (HKCU y HKLM `\Run`) y las clasifica usando `$StartupDB`.

### Categorías de clasificación

| Categoría | Ejemplos | Auto-deshabilitar |
|-----------|----------|-------------------|
| Gaming | Steam, Discord, Epic, Battle.net, Riot | Sí |
| Media | Spotify, AceStream | Sí |
| Browser | Opera | Sí |
| Office | Microsoft Lists | Sí |
| Work | Teams, Citrix | No (KEEP) |
| Hardware | Realtek, AMD Noise Suppression | No (KEEP) |
| Security | KeePass, Vanguard | No (KEEP) |
| Unknown | No está en `$StartupDB` | MANUAL (revisar) |

Además existe `$StartupAutoPatterns`: lista de patrones wildcard para deshabilitar entradas conocidas ruidosas (p. ej. `MicrosoftEdgeAutoLaunch_*`, `AF_uuid_*`).

---

## 4. File Analysis

**Función:** `Collect-FileAnalysisActions`

> Solo opera en rutas ubicadas en la unidad del sistema (`$env:SystemDrive`). Las rutas en otras unidades se omiten con un aviso.

| Comprobación | Umbral | Tipo |
|--------------|--------|------|
| Archivos en el Escritorio | > `DesktopMaxFiles` (20) | MANUAL |
| Archivos sueltos (no accesos directos) en el Escritorio | cualquiera | WARN |
| Archivos en Descargas más antiguos que `DownloadAgeDays` | 60 días | AUTO |
| Archivos individuales grandes en Descargas | > `LargeFileMB` (500 MB) | MANUAL |
| Archivos duplicados por MD5 en `DupScanDirs` | coincidencia exacta | MANUAL |

Los duplicados se detectan calculando el hash MD5 de cada archivo y agrupando los que coinciden.
La eliminación es siempre MANUAL para evitar borrados destructivos no intencionados.

---

## 5. Disk

**Función:** `Collect-DiskActions`

| Comprobación | Umbral | Tipo |
|--------------|--------|------|
| Espacio libre en todas las unidades fijas | < `MinFreeGB` (15 GB) | MANUAL |
| TRIM en unidades SSD | siempre que sea SSD | AUTO |
| Aviso defrag en HDD | siempre que sea HDD | MANUAL |

El TRIM se ejecuta con `Optimize-Volume -DriveLetter X -ReTrim`.

---

## 6. Documents

**Función:** `Collect-DocumentsActions`

Tres capas de análisis sobre Documents, Desktop, Downloads, Pictures, Videos y Music:

### 6a. Auditoría de archivos

| Comprobación | Tipo |
|--------------|------|
| Conteo y tamaño por categoría de extensión | INFO |
| Ejecutables (`.exe`, `.msi`, `.bat`, `.cmd`, `.vbs`) en carpetas de usuario | MANUAL |
| Archivos con nombres sensibles (`password`, `clave`, `token`, etc.) | MANUAL |
| Archivos > 100 MB sin modificar en 6+ meses | MANUAL |
| Subcarpetas vacías | AUTO (elimina) |

### 6b. Clasificación semántica (por nombre de archivo)

Busca patrones en los nombres de archivo para identificar categorías personales:
Identidad, Certificados, Laboral, Fiscal, Bancario, Facturas, Seguros, Médico, Propiedad, Educación, Fotografías, Instaladores.

Los documentos personales reconocidos (`.pdf`, `.docx`, `.xlsx`, etc.) en Desktop o Downloads
se mueven automáticamente a `Documents\<Categoría>` en modo Apply (AUTO).

### 6c. Clasificación por contenido

Lee el interior de archivos de texto (PDF, DOCX, TXT, CSV — máx. 8 MB) y busca
keywords en español e inglés para categorías como Nóminas, AEAT, IBAN, Seguros, Médico, etc.
Los resultados son siempre MANUAL: el script nunca mueve archivos basándose en el contenido.

> Las imágenes y las carpetas de juegos/dev se excluyen del análisis de contenido.

---

## 7. Drivers

**Función:** `Collect-DriversActions`

Detecta dispositivos con errores de driver consultando `Get-CimInstance Win32_PnPEntity` y filtrando los que tienen `ConfigManagerErrorCode -ne 0`.

| Resultado | Tipo |
|-----------|------|
| Dispositivo con error de driver | MANUAL |

> Usa `Get-CimInstance` en lugar del obsoleto `Get-WmiObject` para compatibilidad con PowerShell 7+.

---

## 8. Backup

**Función:** `Collect-BackupActions`

Revisa la fecha de última modificación de los directorios en `BackupDirs` (`Documents` y `Desktop` por defecto).

| Comprobación | Umbral | Tipo |
|--------------|--------|------|
| Carpeta modificada sin backup reciente | > 7 días | MANUAL |
| Recordatorio de estrategia de backup offsite | siempre | MANUAL |

El backup no se realiza automáticamente; solo genera recordatorios MANUAL.

---

## 9. Network

**Función:** `Collect-NetworkActions`

| Comprobación | Tipo |
|--------------|------|
| Adaptadores de red activos con IP, gateway y DNS | INFO |
| Ping a Google DNS (8.8.8.8) | WARN si > 100 ms o inalcanzable |
| Ping a Cloudflare DNS (1.1.1.1) | WARN si > 100 ms o inalcanzable |
| Ping a Quad9 (9.9.9.9) | WARN si > 100 ms o inalcanzable |

Si algún servidor DNS es inalcanzable se registra una acción MANUAL de revisión de conectividad.

---

## 10. Temperature

**Función:** `Collect-TemperatureActions`

Lee las zonas térmicas ACPI del sistema sin herramientas de terceros.

| Umbral | Tipo |
|--------|------|
| < 75 °C | KEEP |
| 75–90 °C | WARN + MANUAL |
| > 90 °C | WARN + MANUAL (crítico) |

> Para temperaturas de GPU es necesario [LibreHardwareMonitor](https://github.com/LibreHardwareMonitor/LibreHardwareMonitor).
> El módulo detecta si está instalado e informa de ello.

---

## 11. Processes

**Función:** `Collect-ProcessActions`

| Comprobación | Tipo |
|--------------|------|
| Top 5 procesos por tiempo de CPU | INFO |
| Top 5 procesos por uso de RAM | INFO |
| Proceso consumiendo > 2 GB de RAM | MANUAL |
