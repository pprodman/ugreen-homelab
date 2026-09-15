SELECT
    fecha AS date,
    TRIM(descripcion) AS description,
    importe AS amount,
    fecha_cargo AS charge_date,

    source_row_id,
    source_hash,
    loaded_at,
    updated_at

FROM {{ source('raw', 'bankinter_card_common_lledo') }}