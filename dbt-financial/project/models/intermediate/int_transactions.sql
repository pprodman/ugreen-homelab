{{ config(materialized='view') }}

WITH base AS (
    SELECT * FROM {{ ref('int_transactions_unioned') }}
),

/* ================================================================
   1. PARTICIPANTES (Normalización frente a \xa0, #$, ; y tildes)
   ================================================================ */
with_participant AS (
    SELECT DISTINCT ON (b.source_hash)
        b.*,
        p.person_name AS participant_name
    FROM base b
    LEFT JOIN {{ ref('master_participants') }} p
        ON TRANSLATE(REGEXP_REPLACE(REPLACE(b.description, CHR(160), ' '), '[^a-zA-Z0-9]+', ' ', 'g'), 'ÁÉÍÓÚáéíóú', 'AEIOUaeiou')
           ILIKE '%' || TRANSLATE(REGEXP_REPLACE(p.keyword, '[^a-zA-Z0-9]+', ' ', 'g'), 'ÁÉÍÓÚáéíóú', 'AEIOUaeiou') || '%'
    ORDER BY b.source_hash, LENGTH(p.keyword) DESC NULLS LAST
),

/* ================================================================
   2. REGLAS DE CATEGORIZACIÓN / COMERCIO
   ================================================================ */
with_mapping AS (
    SELECT
        p.*,
        r.category_id,
        NULLIF(TRIM(r.merchant_name), '') AS rule_merchant,
        r.priority
    FROM with_participant p
    LEFT JOIN {{ source('stg', 'rules_mapping') }} r
        ON TRANSLATE(REGEXP_REPLACE(p.description, '[^a-zA-Z0-9]+', ' ', 'g'), 'ÁÉÍÓÚáéíóú', 'AEIOUaeiou')
           ILIKE '%' || TRANSLATE(REGEXP_REPLACE(r.keyword, '[^a-zA-Z0-9]+', ' ', 'g'), 'ÁÉÍÓÚáéíóú', 'AEIOUaeiou') || '%'
),

mapping_ranked AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY source_hash
            ORDER BY priority DESC NULLS LAST, LENGTH(description) DESC
        ) AS mapping_rank
    FROM with_mapping
),

/* ================================================================
   3. AJUSTES MANUALES (Mapeo exacto de columnas de master_adjustments)
   ================================================================ */
with_adjustments AS (
    SELECT
        m.*,
        a.category_id_override,
        a.merchant_override,
        a.adjustment_type,
        a.adjustment_amount,
        a.reason AS adjustment_reason
    FROM mapping_ranked m
    LEFT JOIN {{ source('stg', 'master_adjustments') }} a
        ON m.source_hash = a.source_hash
    WHERE m.mapping_rank = 1
),

/* ================================================================
   4. RESOLUCIÓN FINAL DE CATEGORÍA Y COMERCIO
   ================================================================ */
resolved AS (
    SELECT
        a.*,

        -- Categoría: Override manual > Regla de negocio > Lógica de personas por signo > Fallback
        COALESCE(
            a.category_id_override,
            a.category_id,
            CASE
                WHEN a.participant_name = 'Lledó Amorós' AND a.amount < 0 AND a.account_ownership = 'personal'
                    THEN 'PAREJA_COMPENSA'
                WHEN a.participant_name = 'Lledó Amorós' AND a.amount > 0 AND a.account_ownership = 'common'
                    THEN 'MOV_FONDEO_COMUN'
                WHEN (a.participant_name IS NOT NULL OR a.transaction_nature = 'BIZUM') AND a.amount > 0
                    THEN CASE WHEN a.transaction_nature = 'BIZUM' THEN 'ING_BIZUM' ELSE 'ING_TRANSFERENCIAS' END
                WHEN (a.participant_name IS NOT NULL OR a.transaction_nature = 'BIZUM') AND a.amount < 0
                    THEN CASE WHEN a.transaction_nature = 'BIZUM' THEN 'VAR_BIZUM' ELSE 'VAR_OTROS' END
                WHEN a.transaction_nature = 'SALARY'              THEN 'ING_NOMINA'
                WHEN a.transaction_nature = 'MORTGAGE_PAYMENT'     THEN 'FIX_HIPOTECA'
                WHEN a.transaction_nature = 'CARD_SETTLEMENT'      THEN 'MOV_LIQ_TARJETA'
                WHEN a.transaction_nature = 'INTERNAL_TRANSFER'    THEN 'MOV_TRASPASO'
                WHEN a.transaction_nature = 'PARTNER_CONTRIBUTION' THEN 'MOV_FONDEO_COMUN'
                WHEN a.transaction_nature = 'LOAN_DISBURSEMENT'    THEN 'CPX_DISPOSICION'
                WHEN a.transaction_nature = 'EXPENSE_REFUND'       THEN 'VAR_DEVOLUCION'
                WHEN a.amount > 0                                  THEN 'ING_TRANSFERENCIAS'
                ELSE 'VAR_OTROS'
            END
        ) AS final_category_id,

        -- Comercio: Override manual > Regla > Nombre del contacto > Heurística de extracto
        COALESCE(
            NULLIF(TRIM(a.merchant_override), ''),
            a.rule_merchant,
            NULLIF(TRIM(a.participant_name), ''),
            CASE 
                WHEN a.account_type = 'card' AND a.description LIKE '%,%' 
                THEN TRIM(SPLIT_PART(a.description, ',', 1)) 
            END,
            CASE 
                WHEN a.description ~* '^(RECIBO|RECIB)\s*\/?' 
                THEN TRIM(REGEXP_REPLACE(a.description, '^(RECIBO|RECIB)\s*\/?\s*', '', 'i')) 
            END,
            'No Identificado'
        ) AS final_merchant

    FROM with_adjustments a
),

/* ================================================================
   5. DIMENSIÓN DE CATEGORÍAS (Consistencia con dim_categories)
   ================================================================ */
with_category AS (
    SELECT
        r.*,
        c.group_name,
        c.category_name,
        c.subcategory_name,
        COALESCE(c.is_pnl, r.is_pnl) AS category_is_pnl,
        COALESCE(c.movement_type, r.movement_type) AS resolved_movement_type
    FROM resolved r
    LEFT JOIN {{ source('stg', 'dim_categories') }} c
        ON r.final_category_id = c.category_id
),

/* ================================================================
   6. CÁLCULOS FINANCIEROS Y REPARTO
   ================================================================ */
final AS (
    SELECT
        -- Identificación y cuenta
        source_hash,
        account_id,
        bank,
        account_type,
        account_ownership,

        -- Fechas (base económica en value_date)
        value_date,
        booking_date,
        DATE_TRUNC('month', value_date)::DATE AS year_month,
        EXTRACT(YEAR FROM value_date)::INTEGER AS year,
        EXTRACT(MONTH FROM value_date)::INTEGER AS month,

        -- Importes originales
        description,
        amount,
        balance,

        -- Clasificación
        transaction_nature,
        resolved_movement_type AS movement_type,
        final_category_id AS category_id,
        group_name,
        category_name,
        subcategory_name,
        final_merchant AS merchant,
        participant_name,

        -- Reparto económico personal
        CASE
            WHEN adjustment_type = 'PARTNER_EXPENSE' THEN 0.00
            WHEN adjustment_type = 'MY_EXPENSE'      THEN amount
            WHEN adjustment_type = 'PARTIAL_EXPENSE' 
                THEN -ROUND((ABS(amount) - ABS(COALESCE(adjustment_amount, 0))) * 0.50, 2)
            WHEN account_ownership = 'personal' THEN amount
            WHEN account_ownership = 'common' AND resolved_movement_type IN ('EXPENSE', 'INCOME')
                THEN ROUND(amount * 0.50, 2)
            ELSE 0.00
        END AS personal_amount,

        CASE
            WHEN adjustment_type = 'PARTNER_EXPENSE' THEN 0.00
            WHEN adjustment_type = 'MY_EXPENSE'      THEN 1.00
            WHEN account_ownership = 'common'        THEN 0.50
            ELSE 1.00
        END AS personal_share_pct,

        -- P&L riguroso heredado de la taxonomía contable
        CASE
            WHEN category_is_pnl = FALSE THEN FALSE
            WHEN resolved_movement_type = 'TRANSFER' THEN FALSE
            WHEN transaction_nature IN ('CARD_SETTLEMENT', 'INTERNAL_TRANSFER', 'PARTNER_CONTRIBUTION') THEN FALSE
            ELSE TRUE
        END AS is_pnl,

        -- Marca de gasto compartido
        CASE
            WHEN category_is_pnl = FALSE THEN FALSE
            WHEN resolved_movement_type = 'TRANSFER' THEN FALSE
            WHEN adjustment_type IN ('PARTNER_EXPENSE', 'MY_EXPENSE') THEN FALSE
            WHEN adjustment_type = 'PARTIAL_EXPENSE' THEN TRUE
            WHEN account_ownership = 'common' THEN TRUE
            ELSE FALSE
        END AS is_shared,

        -- Auditoría
        adjustment_type,
        adjustment_amount,
        adjustment_reason,
        source_row_id,
        loaded_at

    FROM with_category
)

SELECT * FROM final