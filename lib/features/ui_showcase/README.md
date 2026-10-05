# Módulo de Vistas UI & Showcase Interactivo (`features/ui_showcase`)

## Propósito del Módulo
Este módulo fue diseñado específicamente para servir como **entorno de pruebas visuales e interactivas de todas las funcionalidades requeridas por el proyecto**, permitiendo validar de manera directa y tangible cada punto de la matriz MoSCoW y del PDF de Proyecto Final:
1. **Autenticación & MFA**: Flujo interactivo de registro (sin SIM), login y verificación de doble factor con código de 6 dígitos.
2. **Directorio & Búsqueda Exacta**: Validador de búsqueda exacta de "Nombre de Usuario" (`username`).
3. **Sala de Chat 1 a 1**: Mensajería en tiempo real con soporte de fotos, videos, notas de audio, indicador de "Escribiendo..." y doble check azul.
4. **Laboratorio Multimedia**: Grabación de notas de voz con tope estricto de 1 minuto (60 segundos) y cálculo de compresión/ahorro en Supabase Storage.
5. **Simulador Offline**: Activación del interruptor "Sin Internet", lectura del historial persistido y encolamiento de mensajes pendientes de sincronización.
6. **Simulador de Notificaciones Push**: Disparador de alerta push en segundo plano.

## Estructura de Pantallas
- `views/showcase_home_view.dart`: Tablero principal con lista interactiva de requerimientos, métricas de puntaje MoSCoW e indicadores de estado del sistema.
- `views/auth_interactive_view.dart`: Pantalla de prueba para Auth y verificación de token MFA.
- `views/directory_search_view.dart`: Buscador exacto con lista de sugerencias y retroalimentación en tiempo real.
- `views/chat_playground_view.dart`: Interfaz tipo WhatsApp con burbujas de mensaje, adjuntos y reproductor.
- `views/media_recorder_view.dart`: Grabador de audio con cronómetro visual decreciente/creciente a 60 segundos y cálculo de bytes.
- `views/offline_sync_view.dart`: Panel de control de conectividad de red con cola de mensajes locales pendientes.

## Directrices para el Agente / Desarrollador
- **Diseño Limpio y Accesible**: Las vistas provisionales utilizan componentes Material 3 con colores institucionales de FinChat y soporte para contraste adecuado.
- **Transición a Producción**: Cuando se conecten los servicios finales de Supabase, estas vistas pueden transformarse en la UI definitiva o conservarse como suite de pruebas manuales y modo demo para evaluación académica.
