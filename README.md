# Servicio Técnico SZR V6 — proyecto Flutter para Windows

Incluye: panel, órdenes con formulario de dos columnas, clientes sugeridos, estados rápidos, confirmación de entrega y cobro, historial de pagos, Ganancias (ingresos, no utilidad neta), Mi negocio y logo personalizado, informe PDF con rango de fechas, lista negra, presupuestos, clientes, modo claro/oscuro, SQLite sin Internet.

## Instalación
1. Respaldar carpeta actual y datos. No borrar la base de datos SQLite.
2. Copiar `lib`, `assets` y `pubspec.yaml` sobre `C:\proyectos\servicio_tecnico_szr`.
3. En CMD: `flutter create --platforms=windows .`, `flutter pub get`, `flutter run -d windows`.
4. Para el icono Windows, copiar `windows_icon/app_icon.ico` a `windows/runner/resources/app_icon.ico` y ejecutar `flutter build windows --release`.

## Datos anteriores
La migración de SQLite v1 a v2 preserva clientes y órdenes, y convierte los adelantos existentes en movimientos de pago. El directorio de datos se mantiene como `ServicioTecnicoPro` por compatibilidad. No duplicar la importación.

## PDF
El botón Exportar PDF abre el diálogo de impresión/guardar PDF de Windows. Los cobros se filtran por fecha de pago y las órdenes por fecha de ingreso. El saldo pendiente es el saldo actual de todas las órdenes activas (no un saldo histórico al cierre del período). La ganancia neta no se calcula sin registrar costos.

## Limitaciones
Proyecto fuente no compilado en Windows desde este entorno. Requiere Flutter/Visual Studio y resolver dependencias en el primer `flutter pub get` (con Internet para descarga inicial). Verificar compilación y respaldos antes de usar con datos reales.

# 🖥️ SERVICIO TÉCNICO PC

Sistema de gestión de servicios técnicos de computadoras para Windows.

## 📥 Descargar programa

### 💻 Windows

Descarga la última versión de SERVICIO TÉCNICO PC.

[⬇️ **DESCARGAR SERVICIO TÉCNICO PC (.EXE)**](https://github.com/aldosalazar2025-oss/ServicioTecnicoSzr/releases/download/1.1.1/Servicio.Tecnico.SZR.exe)

**Versión:** 1.1.1  
**Tamaño:** 14.9 MB  
**Sistema operativo:** Windows

## 🚀 Instalación

1. Haz clic en el enlace de descarga.
2. Espera a que se descargue el archivo.
3. Abre `Servicio.Tecnico.SZR.exe`.
4. Sigue las indicaciones que aparezcan en pantalla.

## 📌 Información

- **Nombre:** SERVICIO TÉCNICO PC
- **Plataforma:** Computadoras con Windows
- **Formato:** Ejecutable `.exe`


