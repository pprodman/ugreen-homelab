{{ config(
    tags = ['mart', 'finance', 'capex']
) }}

WITH capex_tx AS (
    SELECT * FROM {{ ref('fct_transactions') }}
    WHERE group_name = 'CAPEX' 
       OR category_id IN ('CPX_DISPOSICION', 'CPX_CONSTRUCTORA', 'CPX_TECNICOS', 'CPX_TRAMITES')
)

SELECT
    accrual_month AS year_month,

    -- Salidas / Inversión en Obra (Importe total del proyecto)
    ROUND(SUM(CASE WHEN category_id = 'CPX_CONSTRUCTORA' THEN amount ELSE 0.00 END), 2) AS cost_constructora,
    ROUND(SUM(CASE WHEN category_id = 'CPX_TECNICOS' THEN amount ELSE 0.00 END), 2) AS cost_tecnicos_arquitecto,
    ROUND(SUM(CASE WHEN category_id = 'CPX_TRAMITES' THEN amount ELSE 0.00 END), 2) AS cost_tramites_notaria,

    -- Inversión total mensual en vivienda
    ROUND(SUM(CASE 
        WHEN category_id IN ('CPX_CONSTRUCTORA', 'CPX_TECNICOS', 'CPX_TRAMITES') 
            THEN amount 
        ELSE 0.00 
    END), 2) AS total_project_investment,

    -- Entradas de Financiación (Disposiciones del préstamo de obra)
    ROUND(SUM(CASE WHEN category_id = 'CPX_DISPOSICION' THEN amount ELSE 0.00 END), 2) AS loan_disbursements,

    -- Flujo neto de tesorería en obra (Disposiciones - Pagos de certificaciones)
    ROUND(SUM(CASE 
        WHEN category_id = 'CPX_DISPOSICION' THEN amount 
        WHEN category_id IN ('CPX_CONSTRUCTORA', 'CPX_TECNICOS', 'CPX_TRAMITES') THEN amount
        ELSE 0.00 
    END), 2) AS net_capex_cash_flow

FROM capex_tx
GROUP BY accrual_month
ORDER BY accrual_month DESC