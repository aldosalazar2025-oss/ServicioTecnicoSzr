SERVICIO TÉCNICO SZR V9.2 — CÓDIGO FUENTE

Cambios:
- Separación de 22 píxeles entre hora y selector de responsable.
- Numeración visible ORD-0001... separada del ID interno. Si se eliminan las últimas órdenes, se puede reutilizar el último número; si se borran todas, empieza en 0001. Las órdenes antiguas conservan sus números. ATENCIÓN: reutilizar números de comprobantes antiguos puede causar confusión; guarda copia de los PDF.
- Activación local con contraseña oculta, días configurables y bloqueo tras 3 errores hasta medianoche del día siguiente según reloj de Windows.
- No se borran datos al vencer la licencia.

IMPORTANTE: Esta versión usa licencia LOCAL, NO tiene activación por Internet, servidor ni protección anti-manipulación. No distribuir como un sistema de licencias comercial seguro. La contraseña está verificada por un hash dentro del programa; no es secreto irrecuperable frente a ingeniería inversa. El bloqueo depende del reloj local de Windows y de SharedPreferences.

INSTALACIÓN:
1. Haz respaldo de la base de datos y carpeta de proyecto.
2. Copia lib, assets, pubspec.yaml.
3. flutter create --platforms=windows .
4. flutter pub get
5. flutter run -d windows

La base de datos SQLite migra de versión 4 a 5 conservando los registros existentes. No ha sido posible compilar el proyecto en Windows en este entorno.
