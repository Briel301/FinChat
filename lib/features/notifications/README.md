# Módulo de Notificaciones Push (`features/notifications`)

## Requerimientos MoSCoW & Proyecto Final Cubiertos
- **Should Have (8 pts)**: Notificaciones Push cuando la aplicación está en segundo plano (*background*) o completamente cerrada (*terminated*).
- Aviso instantáneo al recibir nuevos mensajes de texto o multimedia.

## Arquitectura Cloud con Supabase y FCM
Para enviar notificaciones push en segundo plano sin servidor dedicado:

```
[Usuario A envía mensaje]
        │
        ▼
[Supabase: INSERT en tabla messages]
        │
        ▼ (Database Webhook)
[Supabase Edge Function: 'push-dispatcher']
        │
        ▼ (Google FCM v1 API / Apple APNs)
[Dispositivo de Usuario B (Segundo plano / Cerrado)]
        │
        ▼
[Notificación del Sistema Operativo con payload: {chat_id, sender_id}]
```

1. **Tokens de Dispositivo**:
   Al iniciar sesión en un dispositivo, el token FCM se guarda en una tabla `device_tokens`:
   ```sql
   create table public.device_tokens (
     user_id uuid references public.profiles(id) on delete cascade,
     fcm_token text not null,
     platform text not null, -- 'android' | 'ios'
     updated_at timestamp with time zone default now(),
     primary key (user_id, fcm_token)
   );
   ```
2. **Segundo Plano en Flutter**:
   Se registra el handler de segundo plano de nivel superior (`@pragma('vm:entry-point') Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message)`).

## Estructura de Archivos
- `services/notification_service.dart`: Fachada para suscripción de tokens, simulación de alertas push locales y prueba en segundo plano.

## Directrices para el Agente / Desarrollador
1. **Privacidad en Lockscreen**: El payload de la notificación no debe exponer información sensible si el usuario tiene activado el modo de bloqueo privado.
2. **Tap en Notificación**: Al pulsar sobre la notificación del sistema, la app debe enrutar directamente al chat del remitente correspondiente.
