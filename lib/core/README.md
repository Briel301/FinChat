# Módulo Core (Shared Kernel)

## Propósito y Responsabilidades
El módulo `core` contiene la infraestructura transversal compartida por todos los módulos de características (`features`). Su función es evitar la duplicación de código y garantizar consistencia en diseño, conectividad, configuración de Supabase y optimización de rendimiento.

## Contenido del Módulo
- **`theme/`**: Paleta de colores, tipografía, bordes redondeados y estilos Material 3 (estilo FinChat con tonos verde azulado WhatsApp/Fintech y soporte claro/oscuro).
- **`network/`**: Servicio de detección de conectividad (`ConnectivityService`) para activar dinámicamente el modo offline (**Should Have: 7 pts**).
- **`supabase/`**: Configuración central del cliente Supabase (`SupabaseConfig`), claves de entorno y clientes de base de datos/almacenamiento.
- **`utils/`**: 
  - `optimization_utils.dart`: Algoritmos de cálculo de ahorro de datos, estimación de compresión y formateo de fechas/duración de audios.
  - Gestión de operaciones pesadas mediante `compute()` / Isolates para evitar que la UI sufra bloqueos (jank / dropping frames).

## Instrucciones para el Agente / Desarrollador
1. **No acoplar a features**: Este módulo nunca debe importar archivos de `features/*`. Solo provee utilidades puras y de bajo nivel.
2. **Uso de Isolates (`compute`)**: Siempre que se calcule compresión de imágenes o transformación masiva de JSON, implementar o invocar las funciones aisladas en `utils/optimization_utils.dart`.
3. **Manejo de Errores**: Centralizar excepciones comunes de Supabase (errores de red, token expirado, RLS violado) en tipos de datos predecibles.
