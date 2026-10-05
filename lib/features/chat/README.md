# Módulo de Chat & Mensajería 1 a 1 (`features/chat`)

## Requerimientos MoSCoW & Proyecto Final Cubiertos
- **Must Have (10 pts)**: Envío y recepción de mensajes de texto en tiempo real (1 a 1).
- **Must Have**: Lista de conversaciones, persistencia del historial con remitente y marca de tiempo.
- **Should Have (7 pts)**: **Arquitectura Offline**: capacidad de consultar y leer el historial de mensajes sin conexión a internet.
- **Could Have (6 pts)**: Indicador de "Escribiendo..." y confirmación de lectura (**doble check azul**).

## Integración con Supabase Realtime y Soporte Offline
1. **Canales de Supabase Realtime**:
   Las salas de chat 1 a 1 se suscriben mediante WebSockets eficientes a canales específicos:
   ```dart
   final channel = supabase.channel('chat:$chatId')
     ..onPostgresChanges(
       event: PostgresChangeEvent.insert,
       schema: 'public',
       table: 'messages',
       filter: PostgresChangeFilter(
         type: PostgresChangeFilterType.eq,
         column: 'chat_id',
         value: chatId,
       ),
       callback: (payload) => onMessageReceived(payload.newRecord),
     )
     ..onBroadcast(
       event: 'typing',
       callback: (payload) => onTypingReceived(payload),
     )
     ..subscribe();
   ```

2. **Estrategia Offline-First (Local-First Cache)**:
   - Al enviar un mensaje, se guarda inmediatamente en el almacenamiento local con estado `MessageStatus.sending` o `isSynced = false`.
   - Si no hay conexión (o falla la petición), el mensaje permanece visible en la conversación para el usuario.
   - En cuanto `ConnectivityService` detecta reconexión, un trabajador en segundo plano vacía la cola y sincroniza con Supabase.
   - Al abrir un chat, se lee primero de la base de datos local (latencia 0 ms) y luego se piden los deltas a Supabase.

3. **Optimización de Base de Datos (Paginación por Cursor)**:
   NUNCA cargar todos los mensajes históricos de golpe. Utilizar paginación indexada de 25 en 25:
   ```sql
   create index idx_messages_chat_cursor on public.messages (chat_id, created_at desc);
   ```

## Estructura de Archivos
- `models/chat_message.dart`: Modelo inmutable con tipo de mensaje (texto, imagen, video, audio), estado de entrega y timestamps.
- `services/chat_service.dart`: Coordinador de mensajes en memoria y persistencia local, simulación de respuestas e indicadores en tiempo real.

## Directrices para el Agente / Desarrollador
1. **Identificadores UUIDv4**: Generar el `id` del mensaje en el cliente para permitir renderizado inmediato antes de la confirmación del servidor.
2. **Doble Check Azul**: Un mensaje pasa a `read` cuando el destinatario emite un evento `read_receipt` o al abrir la sala de conversación.
