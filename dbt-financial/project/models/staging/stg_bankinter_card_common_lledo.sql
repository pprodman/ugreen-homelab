SELECT
    -- Identificación de la cuenta
    'BANKINTER_CARD_COMMON_LLEDO'::VARCHAR(50) AS account_id,

    -- Fechas
    fecha::DATE                                AS booking_date,
    fecha_cargo::DATE                          AS billing_date,

    -- Movimiento
    TRIM(descripcion)::TEXT                    AS description,
    importe::NUMERIC(18,2)                     AS amount,

    -- Trazabilidad
    source_row_id::BIGINT                      AS source_row_id,
    source_hash::VARCHAR(64)                   AS source_hash,
    loaded_at::TIMESTAMPTZ                     AS loaded_at,
    updated_at::TIMESTAMPTZ                    AS updated_at

FROM {{ source('raw', 'bankinter_card_common_lledo') }}
ORDER BY source_row_id ASC