-- ==============================================================================
-- Script de Configuración: Bucket 'chat_media' y Políticas RLS en Supabase
-- Proyecto: FinChat
-- Propósito: Almacenamiento seguro de medios (fotos, videos, notas de voz <= 1 min)
-- ==============================================================================

-- 1. Crear el bucket 'chat_media' en storage.buckets con límite de 50 MB
--    Configurado como 'public = false' para requerir autenticación en lecturas.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'chat_media',
    'chat_media',
    false, -- Bucket privado/autenticado: exige token JWT para lectura/descarga
    52428800, -- Límite máximo: 50 MB en bytes (50 * 1024 * 1024)
    ARRAY[
        'image/jpeg',
        'image/png',
        'image/webp',
        'image/gif',
        'audio/aac',
        'audio/m4a',
        'audio/mp4',
        'audio/mpeg',
        'audio/ogg',
        'audio/wav',
        'video/mp4',
        'video/quicktime',
        'video/webm'
    ]::text[]
)
ON CONFLICT (id) DO UPDATE SET
    public = EXCLUDED.public,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

-- 2. Habilitar Row Level Security (RLS) en la tabla storage.objects
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

-- 3. Limpiar políticas previas para evitar colisiones al reaplicar
DROP POLICY IF EXISTS "Chat Media - Lectura Autenticados" ON storage.objects;
DROP POLICY IF EXISTS "Chat Media - Insercion Propietario" ON storage.objects;
DROP POLICY IF EXISTS "Chat Media - Eliminacion Propietario" ON storage.objects;
DROP POLICY IF EXISTS "Chat Media - Actualizacion Propietario" ON storage.objects;

-- 4. POLÍTICA DE LECTURA (SELECT):
--    Permitida exclusivamente para usuarios autenticados dentro del bucket 'chat_media'.
CREATE POLICY "Chat Media - Lectura Autenticados"
ON storage.objects
FOR SELECT
TO authenticated
USING (
    bucket_id = 'chat_media'
);

-- 5. POLÍTICA DE INSERCIÓN (INSERT):
--    Permitida únicamente si:
--    a) El usuario tiene una sesión activa ('authenticated').
--    b) El destino es el bucket 'chat_media'.
--    c) El nombre del archivo sigue estrictamente la jerarquía: chat_id/sender_id/filename.
--    d) El 'sender_id' (segundo segmento de la ruta) coincide con el UID del usuario autenticado (auth.uid()).
--    e) El tamaño de archivo no supera 50 MB (52,428,800 bytes).
CREATE POLICY "Chat Media - Insercion Propietario"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'chat_media'
    -- Garantiza estructura exacta de 3 niveles: chat_id/sender_id/filename
    AND name ~ '^[^/]+/[^/]+/[^/]+$'
    -- Valida que el segundo segmento (sender_id) sea el ID del usuario en sesión
    AND (storage.foldername(name))[2] = (auth.uid())::text
    -- Validación adicional de tamaño a nivel de metadatos (50 MB)
    AND (
        (metadata->>'size')::bigint <= 52428800
        OR metadata->>'size' IS NULL
    )
);

-- 6. POLÍTICA DE ELIMINACIÓN (DELETE):
--    Permite al remitente eliminar únicamente sus propios archivos subidos.
CREATE POLICY "Chat Media - Eliminacion Propietario"
ON storage.objects
FOR DELETE
TO authenticated
USING (
    bucket_id = 'chat_media'
    AND (storage.foldername(name))[2] = (auth.uid())::text
);

-- 7. POLÍTICA DE ACTUALIZACIÓN (UPDATE):
--    Permite actualizar metadatos únicamente al propietario del archivo.
CREATE POLICY "Chat Media - Actualizacion Propietario"
ON storage.objects
FOR UPDATE
TO authenticated
USING (
    bucket_id = 'chat_media'
    AND (storage.foldername(name))[2] = (auth.uid())::text
)
WITH CHECK (
    bucket_id = 'chat_media'
    AND (storage.foldername(name))[2] = (auth.uid())::text
);
