WITH base AS (
    SELECT
        t.source_hash,
        t.account_id,
        t.booking_date,
        t.value_date,
        t.description,
        t.amount,
        t.balance,
        t.source_row_id,
        t.loaded_at,
        da.bank,
        da.account_type,
        da.owner AS account_ownership
    FROM {{ ref('stg_bankinter_account_personal') }} t
    LEFT JOIN {{ source('stg', 'dim_account') }} da
        ON t.account_id = da.account_id
),

classified_nature AS (
    SELECT
        *,
        CASE
            -- 1. Liquidación mensual de tarjeta
            WHEN description ~* 'RECIBO PLATINUM' 
                THEN 'CARD_SETTLEMENT'
            -- 2. Pagos/Cobros por Bizum (evaluar antes de nombres personales)
            WHEN description ~* 'BIZUM' 
                THEN 'BIZUM'
            -- 3. Retiradas de efectivo en ventanilla o cajero (prioridad sobre nombres propios)
            WHEN description ~* '^(CAJA\s+[0-9]+|CAJERO|TRANSF\s+A\s+CAJERO)' 
                THEN 'REGULAR'
            -- 4. Traspasos internos propios
            WHEN description ~* 'CUENTA T[UÚ] Y YO|RECARGA REVOLUT|TRASPASO INTERNO|PABLO RODRIGUEZ' 
                THEN 'INTERNAL_TRANSFER'
            -- 5. Ingresos salariales y prestaciones
            WHEN description ~* 'TRANSF NOMI|PRESTACIONES SEGURIDAD SOCIAL' 
                THEN 'SALARY'
            -- 6. Reembolsos comerciales estrictos (patrón delimitado + importe positivo)
            WHEN description ~* '\yANUL' AND amount > 0 
                THEN 'EXPENSE_REFUND'
            -- 7. Recibos y transacciones ordinarias
            ELSE 'REGULAR'
        END AS transaction_nature
    FROM base
)

SELECT
    -- Fechas
    value_date,
    booking_date,

    -- Transacción
    description,
    amount,
    balance,
    amount AS personal_amount,

    -- Clasificación analítica derivada
    transaction_nature,

    CASE
        WHEN transaction_nature IN ('CARD_SETTLEMENT', 'INTERNAL_TRANSFER') THEN 'TRANSFER'
        WHEN transaction_nature = 'EXPENSE_REFUND' THEN 'EXPENSE' -- Contra-gasto (reduce gasto en suma algebraica)
        WHEN amount > 0 THEN 'INCOME'
        WHEN amount < 0 THEN 'EXPENSE'
        ELSE 'NEUTRAL' -- Evita valores NULL en operaciones de importe 0.00
    END AS movement_type,

    (transaction_nature NOT IN ('CARD_SETTLEMENT', 'INTERNAL_TRANSFER')) AS is_pnl,

    -- Identificadores y dimensiones de cuenta
    account_id,
    bank,
    account_type,
    account_ownership,
    source_hash,

    -- Auditoría
    source_row_id,
    loaded_at

FROM classified_nature
ORDER BY source_row_id ASC