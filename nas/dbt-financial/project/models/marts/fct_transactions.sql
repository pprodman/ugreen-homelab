{{ config(
    tags = ['mart', 'finance', 'core']
) }}

WITH base AS (
    SELECT * FROM {{ ref('int_transactions') }}
),

enriched AS (
    SELECT
        source_hash,
        account_id,
        bank,
        account_type,
        account_ownership,

        -- Fechas estándar
        value_date,
        booking_date,
        year_month AS bank_year_month,
        year,
        month,

        -- ================================================================
        -- MES DE DEVENGO (Accrual Month)
        -- Nóminas cobradas en días 1-16 se asignan a M-1
        -- ================================================================
        CASE
            WHEN category_id IN ('ING_NOMINA', 'ING_PRESTACIONES', 'ING_INDEMNIZACION') 
                 AND EXTRACT(DAY FROM value_date) <= 16
                THEN (DATE_TRUNC('month', value_date) - INTERVAL '1 month')::DATE
            ELSE DATE_TRUNC('month', value_date)::DATE
        END AS accrual_month,

        -- Atributos de clasificación
        description,
        amount,
        balance,
        transaction_nature,
        movement_type,
        category_id,
        group_name,
        category_name,
        subcategory_name,
        merchant,
        participant_name,

        -- Importes analíticos
        personal_amount,
        personal_share_pct,
        is_pnl,
        is_shared,

        -- Auditoría
        adjustment_type,
        adjustment_amount,
        adjustment_reason,
        loaded_at

    FROM base
)

SELECT * FROM enriched