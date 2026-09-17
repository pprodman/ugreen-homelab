SELECT
    -- Identificación de la cuenta
    'REVOLUT'::VARCHAR(50)                  AS account_id,

    -- Fechas
    fecha_inicio::DATE                      AS value_date,
    fecha_fin::DATE                         AS booking_date,

    -- Movimiento
    TRIM(descripcion)::TEXT                 AS description,
    importe::NUMERIC(18,2)                  AS amount,
    saldo::NUMERIC(18,2)                    AS balance,
    COALESCE(comision, 0)::NUMERIC(18,2)    AS fee,
    UPPER(TRIM(divisa))::VARCHAR(3)         AS currency,

    -- Clasificación original
    tipo::VARCHAR(50)                       AS raw_transaction_type,
    --producto::VARCHAR(50)                   AS raw_product,
    UPPER(TRIM(state))::VARCHAR(20)         AS status,

    -- Trazabilidad
    source_row_id::BIGINT                   AS source_row_id,
    source_hash::VARCHAR(64)                AS source_hash,
    loaded_at::TIMESTAMPTZ                  AS loaded_at,
    updated_at::TIMESTAMPTZ                 AS updated_at

FROM {{ source('raw', 'revolut_account') }}
WHERE UPPER(TRIM(state)) = 'COMPLETADO'