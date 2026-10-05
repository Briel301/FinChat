# Módulo de Usuarios & Directorio (`features/users`)

## Requerimientos MoSCoW & Proyecto Final Cubiertos
- **Must Have (10 pts)**: Búsqueda de usuarios mediante **coincidencia exacta** de "Nombre de Usuario".
- **Must Have**: Perfil de usuario (Nombre o alias, fotografía de perfil e información básica/biografía).
- Independencia total de agenda telefónica o números SIM.

## Optimización de Base de Datos y Supabase Storage
1. **Índice B-Tree para Coincidencia Exacta**:
   Para evitar escaneos secuenciales lentos (`Seq Scan`) en PostgreSQL y garantizar respuesta en milisegundos con cero sobrecosto en Supabase:

```sql
-- Índice B-Tree insensible a mayúsculas para búsqueda exacta instantánea:
create unique index idx_profiles_username_lower on public.profiles (lower(username));

-- Consulta optimizada:
select id, username, full_name, avatar_url, bio, created_at 
from public.profiles 
where lower(username) = lower(:searched_username)
limit 1;
```

2. **Ahorro en Almacenamiento de Avatares**:
   - Redimensionar la foto de perfil en el cliente a un máximo de `256x256` píxeles en formato **WebP**.
   - Peso esperado: **< 35 KB** por avatar (frente a 3-5 MB de una foto cruda de cámara).
   - El archivo se sube al bucket `avatars` en Supabase Storage con política de reemplazo `upsert: true`.

## Estructura de Archivos
- `models/user_profile.dart`: Modelo inmutable de perfil de usuario.
- `services/user_service.dart`: Lógica de consulta por coincidencia exacta, actualización de perfil y simulación de base de datos.

## Directrices para el Agente / Desarrollador
- **Búsqueda Exacta**: NUNCA utilizar operadores `ILIKE '%term%'` en la búsqueda principal de usuarios, ya que el requerimiento MoSCoW especifica **coincidencia exacta** (`=`).
- **No duplicar avatares**: Al actualizar la foto de perfil, sobrescribir el archivo en Supabase Storage usando como nombre `user_id.webp` para no acumular basura huérfana en el bucket.
