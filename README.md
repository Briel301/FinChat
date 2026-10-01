# FlutterMSG

Aplicación de mensajería instantánea multiplataforma, inspirada en WhatsApp, que permite la comunicación entre usuarios a través de Internet sin depender de un número telefónico o tarjeta SIM. Utiliza una arquitectura Backend as a Service (BaaS) con Supabase/Firebase.

## 📜 Reglas del Repositorio

### Flujo de Trabajo (Git Workflow)
Este proyecto utiliza **GitHub Flow** (NO git-flow).
1. La rama `main` siempre debe ser funcional y estar lista para despliegue.
2. Todo el desarrollo de nuevas características o corrección de bugs debe hacerse en ramas descriptivas creadas a partir de `main` (ej. `feature/autenticacion`, `bugfix/envio-imagenes`).
3. Abrir un Pull Request (PR) hacia `main` cuando el trabajo en la rama esté listo.
4. Una vez revisado, se hace merge a `main` y la rama de la característica se puede eliminar.

### Commits Atómicos
- Es obligatorio el uso de **commits atómicos**: cada commit debe representar un único cambio lógico (una funcionalidad específica, una corrección, un refactor) y nunca debe romper la compilación del proyecto.
- No agrupar múltiples cambios no relacionados en un solo commit.
- Usar mensajes de commit claros, en imperativo y descriptivos (se recomienda usar *Conventional Commits* como `feat:`, `fix:`, `docs:`).

## 🚀 Funcionalidades Principales
- Autenticación básica sin validación de correo.
- Envío y recepción de mensajes, imágenes (comprimidas) y notas de audio.
- Arquitectura Offline-first (lectura de mensajes sin internet).
- Notificaciones Push.
