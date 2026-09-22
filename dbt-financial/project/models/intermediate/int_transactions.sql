WITH base_unioned AS (
    SELECT * FROM {{ ref('int_transactions_unioned') }}
),

-- 1. Normalización semántica de Bizums
bizum_normalized AS (
    SELECT
        u.*,
        CASE 
            WHEN b.bizum_name IS NOT NULL THEN 'Bizum: ' || b.bizum_name
            ELSE u.description 
        END                                AS clean_description,
        b.bizum_name                       AS bizum_entity
    FROM base_unioned u
    LEFT JOIN {{ source('stg', 'master_bizum') }} b
        ON u.transaction_nature = 'BIZUM'
       AND u.description ILIKE '%' || b.keyword || '%'
),

-- 2. Detección automática por reglas de palabra clave
best_keyword_match AS (
    SELECT DISTINCT ON (t.source_hash)
        t.*,
        r.category_id                             AS detected_category_id,
        COALESCE(t.bizum_entity, r.merchant_name) AS detected_merchant
    FROM bizum_normalized t
    LEFT JOIN {{ source('stg', 'rules_mapping') }} r
        ON t.description ILIKE '%' || r.keyword || '%'
        OR t.clean_description ILIKE '%' || r.keyword || '%'
    ORDER BY 
        t.source_hash, 
        r.priority DESC NULLS LAST, 
        LENGTH(r.keyword) DESC NULLS LAST
),

-- 3. Aplicación de ajustes manuales (overrides)
adjustments_applied AS (
    SELECT
        m.*,
        adj.adjustment_type,
        adj.adjustment_amount,
        adj.reason AS adjustment_reason,

        -- Prevalencia de categoría: Override manual > Detección por regla
        COALESCE(adj.category_id_override, m.detected_category_id) AS resolved_category_id,

        -- Prevalencia de comercio: Override manual > Comercio detectado > No Identificado
        COALESCE(adj.merchant_override, m.detected_merchant, 'No Identificado') AS merchant_name

    FROM best_keyword_match m
    -- Ajusta el nombre de la tabla según tengas master_adjustments o master_djustments
    LEFT JOIN {{ source('stg', 'master_adjustments') }} adj
        ON m.source_hash = adj.source_hash
),

-- 4. Cálculo de importes personales y cruce dimensional con dim_categories
final_intermediate AS (
    SELECT
        a.value_date,
        a.booking_date,
        a.description AS raw_description,
        a.clean_description,
        a.amount,
        a.balance,

        -- A. LÓGICA DE REPARTO PERSONAL
        CASE
            -- Caso 1: Gasto 100% de la pareja -> Tu coste es 0 €
            WHEN a.adjustment_type = 'PARTNER_EXPENSE' THEN 0.00

            -- Caso 2: Gasto 100% tuyo asumido en cuenta común -> Tu coste es el 100%
            WHEN a.adjustment_type = 'MY_EXPENSE' THEN a.amount

            -- Caso 3: Gasto mixto -> (Total - Parte exclusiva pareja) / 2
            WHEN a.adjustment_type = 'PARTIAL_EXPENSE' AND a.adjustment_amount IS NOT NULL THEN
                ROUND(
                    (ABS(a.amount) - ABS(a.adjustment_amount)) * 0.5 * (CASE WHEN a.amount < 0 THEN -1 ELSE 1 END),
                    2
                )

            -- Default: Importe personal calculado en la capa staging/intermediate base
            ELSE a.personal_amount
        END AS personal_amount,

        -- B. FLAG DE GASTO COMPARTIDO
        CASE
            WHEN a.adjustment_type IN ('PARTNER_EXPENSE', 'MY_EXPENSE') THEN FALSE
            WHEN a.account_ownership = 'common' THEN TRUE
            ELSE FALSE
        END AS is_shared,

        -- C. METADATOS CONTABLES
        a.transaction_nature,
        COALESCE(cat.movement_type, a.movement_type) AS movement_type,
        COALESCE(cat.is_pnl, a.is_pnl)               AS is_pnl,

        -- D. TAXONOMÍA OFICIAL
        cat.category_id,
        COALESCE(cat.group_name, 
            CASE 
                WHEN NOT COALESCE(cat.is_pnl, a.is_pnl) THEN 'Movimientos Operativos'
                WHEN a.amount > 0 THEN 'Ingresos'
                ELSE 'Gastos Variables'
            END
        ) AS group_name,

        COALESCE(cat.category_name, '-')       AS category_name,
        COALESCE(cat.subcategory_name, '-')  AS subcategory_name,

        -- E. ATRIBUTOS DE COMERCIO Y CUENTA
        a.merchant_name,
        a.account_id,
        a.bank,
        a.account_type,
        a.account_ownership,
        a.source_hash,
        a.source_row_id,
        a.adjustment_type,
        a.adjustment_reason,
        a.loaded_at

    FROM adjustments_applied a
    LEFT JOIN {{ source('stg', 'dim_categories') }} cat
        ON a.resolved_category_id = cat.category_id
)

SELECT * FROM final_intermediate