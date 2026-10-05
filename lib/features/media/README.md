# Módulo Multimedia & Hardware (`features/media`)

## Requerimientos MoSCoW & Proyecto Final Cubiertos
- **Must Have (10 pts)**: Envío y recepción de imágenes desde galería.
- **Must Have**: Uso directo de la cámara para capturar y enviar fotografías.
- **Must Have (10 pts)**: Envío y recepción de videos con previsualización/reproducción.
- **Must Have (10 pts)**: Envío y recepción de notas de audio con **límite estricto de máximo 1 minuto (60 segundos)**.
- **Permisos Nativos**: Cámara (`CAMERA`), micrófono (`RECORD_AUDIO`), almacenamiento/galería (`READ_MEDIA_IMAGES`, `READ_MEDIA_VIDEO`).

## Estrategia de Ahorro Extremo en Supabase Storage sin Pérdida de Calidad
Para no incurrir en sobrecostos de almacenamiento ni facturación de ancho de banda (Egress) en Supabase:

1. **Pipeline de Imágenes (WebP)**:
   - Toda foto tomada con cámara (3-8 MB) se procesa en el dispositivo antes de transmitirse.
   - Conversión a formato **WebP**, redimensionamiento a máximo `1080px` de ancho/alto y calidad al `78%`.
   - **Resultado**: Archivos de entre **120 KB y 250 KB** (ahorro superior al 80%) idénticos visualmente en pantallas Retina/AMOLED.
2. **Pipeline de Audio (Voz Humana en AAC Mono 32 kbps)**:
   - Configuración de grabación: Codec AAC/M4A, canal único (mono), frecuencia 44.1 kHz, bitrate de 32 kbps (optimizado para voz).
   - Un audio completo de 1 minuto pesa **menos de 250 KB** (frente a 10 MB de un audio sin compresión).
   - Auto-cierre forzado al cumplirse 60 segundos.
3. **Pipeline de Video**:
   - Limitación de resolución a 720p y compresión con bitrate adaptativo antes del upload.
4. **Caché Local de Medios (Egress Zero)**:
   - Una vez que un usuario descarga una imagen o audio, se guarda en el directorio de caché local del dispositivo. Las siguientes visualizaciones se leen de disco local sin volver a llamar a Supabase Storage.

## Prevención de Congelamiento de UI (Zero UI Jank / 60-120 FPS)
- **Ejecución en Isolates**: El procesamiento de compresión y lectura de bytes de archivos grandes se ejecuta en un hilo secundario mediante `compute()`. El hilo principal de Flutter nunca se detiene, permitiendo que las animaciones y el scroll sigan a 60/120 FPS.

## Estructura de Archivos
- `models/media_attachment.dart`: Entidad con metadatos de medios, tamaño original, tamaño comprimido y ratio de ahorro.
- `services/media_service.dart`: Fachada de captura, compresión en background y temporizador estricto de 60 segundos.

## Directrices para el Agente / Desarrollador
1. **Temporizador de 60s**: Al grabar audio, el servicio debe detener la grabación automáticamente cuando el cronómetro alcance 60 segundos y emitir el archivo resultante.
2. **Manejo de Permisos**: Si el usuario deniega el permiso de cámara o micrófono, mostrar un diálogo informativo accesible sin crashear la aplicación.
