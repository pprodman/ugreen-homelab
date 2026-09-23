{{ config(
    materialized = 'view',
    tags = ['intermediate', 'financial_core']
) }}

WITH base_unioned AS (
    SELECT * FROM {{ ref('int_transactions_unioned') }}
),

-- 1. Normalización de descripciones de Bizum
bizum_normalized AS (
    SELECT
        b.*,
        CASE 
            WHEN b.transaction_nature = 'BIZUM' AND mb.bizum_name IS NOT NULL 
                THEN 'Bizum: ' || mb.bizum_name
            ELSE b.description 
        END AS clean_description,
        mb.bizum_name AS bizum_person
    FROM base_unioned b
    LEFT JOIN {{ source('stg', 'master_bizum') }} mb
        ON b.transaction_nature = 'BIZUM'
       AND b.description ILIKE '%' || mb.keyword || '%'
),

-- 2. Motor de reglas: asignación determinista de categoría y merchant
rules_matched AS (
    SELECT DISTINCT ON (b.source_hash)
        b.*,
        r.category_id   AS matched_category_id,
        r.merchant_name AS matched_merchant_name
    FROM bizum_normalized b
    LEFT JOIN {{ source('stg', 'rules_mapping') }} r
        ON b.description ILIKE '%' || r.keyword || '%'
        OR b.clean_description ILIKE '%' || r.keyword || '%'
    ORDER BY 
        b.source_hash, 
        r.priority DESC NULLS LAST, 
        LENGTH(r.keyword) DESC NULLS LAST
),

-- 3. Incorporación de Overrides manuales (master_adjustments)
adjustments_applied AS (
    SELECT
        r.*,
        adj.category_id_override,
        adj.merchant_override,
        adj.adjustment_type,
        adj.adjustment_amount,
        adj.reason AS adjustment_reason,

        -- Resolución final de category_id
        COALESCE(
            adj.category_id_override,
            r.matched_category_id,
            CASE
                WHEN r.transaction_nature = 'SALARY'               THEN 'ING_NOMINA'
                WHEN r.transaction_nature = 'MORTGAGE_PAYMENT'     THEN 'FIX_HIPOTECA'
                WHEN r.transaction_nature = 'CARD_SETTLEMENT'      THEN 'MOV_LIQ_TARJETA'
                WHEN r.transaction_nature = 'INTERNAL_TRANSFER'    THEN 'MOV_TRASPASO'
                WHEN r.transaction_nature = 'PARTNER_CONTRIBUTION' THEN 'MOV_FONDEO_COMUN'
                WHEN r.transaction_nature = 'LOAN_DISBURSEMENT'    THEN 'CPX_DISPOSICION'
                WHEN r.transaction_nature = 'EXPENSE_REFUND'       THEN 'VAR_DEVOLUCION'
                WHEN r.transaction_nature = 'REWARD'               THEN 'ING_RENDIMIENTOS'
                WHEN r.amount > 0                                  THEN 'ING_TRANSFERENCIAS'
                ELSE 'VAR_OTROS'
            END
        ) AS final_category_id,

        -- Resolución final del comercio o persona
        COALESCE(
            adj.merchant_override,
            r.matched_merchant_name,
            r.bizum_person,
            CASE 
                WHEN r.account_type = 'card' AND r.description LIKE '%,%' 
                THEN TRIM(SPLIT_PART(r.description, ',', 1))
            END,
            CASE 
                WHEN r.description ~* '^(RECIBO|RECIB)\s*\/?' 
                THEN TRIM(REGEXP_REPLACE(r.description, '^(RECIBO|RECIB)\s*\/?\s*', '', 'i'))
            END,
            'No Identificado'
        ) AS final_merchant_name

    FROM rules_matched r
    LEFT JOIN {{ source('stg', 'master_adjustments') }} adj
        ON r.source_hash = adj.source_hash
),

-- 4. Cruce con taxonomía oficial dim_categories
dimensional_enrichment AS (
    SELECT
        a.*,
        cat.group_name,
        cat.category_name,
        cat.subcategory_name,
        COALESCE(cat.is_pnl, a.is_pnl) AS resolved_is_pnl,
        COALESCE(cat.movement_type, a.movement_type) AS resolved_movement_type
    FROM adjustments_applied a
    LEFT JOIN {{ source('stg', 'dim_categories') }} cat
        ON a.final_category_id = cat.category_id
),

-- 5. Lógica de negocio contable: personal_amount e is_shared
final_calculations AS (
    SELECT
        -- Fechas
        value_date,
        booking_date,

        -- Métricas e importes
        amount,

        -- Cálculo de personal_amount con soporte a compensaciones de pareja
        CASE
            -- A. Overrides manuales
            WHEN adjustment_type = 'PARTNER_EXPENSE' THEN 0.00
            WHEN adjustment_type = 'MY_EXPENSE'      THEN amount
            WHEN adjustment_type = 'PARTIAL_EXPENSE' 
                THEN -ROUND((ABS(amount) - ABS(COALESCE(adjustment_amount, 0))) * 0.5, 2)

            -- B. Según titularidad de la cuenta
            WHEN account_ownership = 'personal' THEN amount
            WHEN account_ownership = 'common' AND resolved_movement_type = 'EXPENSE'
                THEN ROUND(amount * 0.5, 2)
            WHEN account_ownership = 'common' AND resolved_movement_type = 'INCOME'
                THEN ROUND(amount * 0.5, 2)

            -- C. Movimientos neutros / tesorería
            ELSE 0.00
        END AS personal_amount,

        balance,

        -- Flags contables de control
        resolved_is_pnl AS is_pnl,

        -- Flag estricto de gasto compartido
        CASE
            WHEN NOT resolved_is_pnl THEN FALSE
            WHEN resolved_movement_type = 'TRANSFER' THEN FALSE
            WHEN adjustment_type IN ('PARTNER_EXPENSE', 'MY_EXPENSE') THEN FALSE
            WHEN adjustment_type = 'PARTIAL_EXPENSE' THEN TRUE
            WHEN account_ownership = 'common' THEN TRUE
            ELSE FALSE
        END AS is_shared,

        resolved_movement_type AS movement_type,
        transaction_nature,

        -- Taxonomía dimensional
        final_category_id AS category_id,
        group_name,
        category_name,
        subcategory_name,

        -- Entidad y descripciones
        final_merchant_name AS merchant_name,
        clean_description,
        description AS raw_description,

        -- Contexto de cuenta
        account_id,
        bank,
        account_type,
        account_ownership,

        -- Auditoría y ajustes (al final)
        adjustment_type,
        adjustment_amount,
        adjustment_reason,
        loaded_at,
        source_row_id,
        source_hash

    FROM dimensional_enrichment
)

SELECT * FROM final_calculations