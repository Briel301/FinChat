# Módulo de Autenticación & MFA (`features/auth`)

## Requerimientos MoSCoW & Proyecto Final Cubiertos
- **Must Have (10 pts)**: Autenticación MFA con usuario, contraseña y correo.
- **Must Have**: Registro e inicio de sesión independiente de SIM, chip o número telefónico.
- Identificación de usuario mediante correo y `username` único.
- Cierre de sesión y persistencia segura de token JWT.

## Arquitectura de Datos e Integración con Supabase
- **Mecanismo Auth**: Supabase Auth (`supabase.auth.signUp`, `signInWithPassword`).
- **Doble Factor (MFA)**:
  - Opción A: Supabase MFA con TOTP (`supabase.auth.mfa.enroll`, `challengeAndVerify`).
  - Opción B: Código OTP de 6 dígitos enviado por correo electrónico.
- **Tabla `profiles`**:
  Al registrarse un usuario con éxito, un trigger de PostgreSQL (`on_auth_user_created`) inserta automáticamente el registro en la tabla pública `public.profiles` con su `username` único, evitando discrepancias de sincronización.

```sql
-- Trigger en Supabase PostgreSQL para perfiles automáticos:
create function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, username, email, full_name, avatar_url, created_at)
  values (new.id, new.raw_user_meta_data->>'username', new.email, new.raw_user_meta_data->>'full_name', null, now());
  return new;
end;
$$ language plpgsql security definer;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();
```

## Estructura de Archivos
- `models/user_session.dart`: Entidad inmutable que representa la sesión activa y el estado del paso MFA.
- `services/auth_service.dart`: Fachada del servicio de autenticación con simulación reactiva de inicio de sesión, envío de código MFA y verificación.

## Directrices para el Agente / Desarrollador
1. **Validación de Username**: Impedir caracteres especiales y espacios. Debe ser alfanumérico en minúsculas.
2. **Estado de MFA**: Ningún usuario debe acceder a la pantalla principal o al chat sin que `isMfaVerified == true`.
3. **Manejo de Errores**: Mostrar mensajes claros al usuario ante contraseñas débiles o códigos MFA caducados.
