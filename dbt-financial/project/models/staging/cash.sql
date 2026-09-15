SELECT
    fecha AS date,
    TRIM(descripcion) AS description,
    importe AS amount,

    source_row_id,
    source_hash,
    loaded_at,
    updated_at

FROM {{ source('raw', 'cash') }}