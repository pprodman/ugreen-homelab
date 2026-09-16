{{ config(
    materialized='view'
) }}

SELECT
    -- Identificación de la cuenta
    'BANKINTER_PERSONAL'::VARCHAR(50)       AS account_id,

    -- Fechas
    fecha_contable::DATE                    AS booking_date,
    fecha_valor::DATE                       AS value_date,

    -- Movimiento
    TRIM(descripcion)::TEXT                 AS description,
    importe::NUMERIC(18,2)                  AS amount,
    saldo::NUMERIC(18,2)                    AS balance,

    -- Trazabilidad
    source_row_id::BIGINT                   AS source_row_id,
    source_hash::VARCHAR(64)                AS source_hash,
    loaded_at::TIMESTAMPTZ                  AS loaded_at,
    updated_at::TIMESTAMPTZ                 AS updated_at

FROM {{ source('raw', 'bankinter_account_personal') }}