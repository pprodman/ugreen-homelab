{{ config(
    tags = ['mart', 'finance', 'pnl']
) }}

WITH tx AS (
    SELECT * FROM {{ ref('fct_transactions') }}
)

SELECT
    accrual_month AS year_month,
    EXTRACT(YEAR FROM accrual_month)::INT AS year,
    EXTRACT(MONTH FROM accrual_month)::INT AS month,

    -- ================================================================
    -- 1. P&L PERSONAL (personal_amount)
    -- ================================================================
    -- Ingresos personales (Nóminas, Bizums cobrados, rendimientos, etc.)
    ROUND(SUM(CASE 
        WHEN is_pnl = TRUE AND movement_type = 'INCOME' 
            THEN personal_amount 
        ELSE 0.00 
    END), 2) AS personal_income,

    -- Gastos personales totales (Fijos + Variables + Devoluciones)
    ROUND(SUM(CASE 
        WHEN is_pnl = TRUE AND movement_type IN ('EXPENSE', 'EXPENSE_REFUND') 
            THEN personal_amount 
        ELSE 0.00 
    END), 2) AS personal_expense,

    -- Desglose por grupo
    ROUND(SUM(CASE 
        WHEN is_pnl = TRUE AND group_name = 'Gastos Fijos' 
            THEN personal_amount 
        ELSE 0.00 
    END), 2) AS personal_fixed_expenses,

    ROUND(SUM(CASE 
        WHEN is_pnl = TRUE AND group_name = 'Gastos Variables' 
            THEN personal_amount 
        ELSE 0.00 
    END), 2) AS personal_variable_expenses,

    ROUND(SUM(CASE 
        WHEN is_pnl = TRUE AND group_name = 'Gastos Financieros' 
            THEN personal_amount 
        ELSE 0.00 
    END), 2) AS personal_financial_expenses,

    -- Ahorro neto individual (Ingresos + Gastos)
    ROUND(SUM(CASE 
        WHEN is_pnl = TRUE 
            THEN personal_amount 
        ELSE 0.00 
    END), 2) AS personal_net_savings,

    -- Tasa de ahorro (%)
    CASE
        WHEN SUM(CASE WHEN is_pnl = TRUE AND movement_type = 'INCOME' THEN personal_amount ELSE 0.00 END) > 0
        THEN ROUND(
            (
                SUM(CASE WHEN is_pnl = TRUE THEN personal_amount ELSE 0.00 END)
                / SUM(CASE WHEN is_pnl = TRUE AND movement_type = 'INCOME' THEN personal_amount ELSE 0.00 END)
            ) * 100.0, 
            2
        )
        ELSE 0.00
    END AS savings_rate_pct,

    -- ================================================================
    -- 2. ECONOMÍA DEL HOGAR (100% de la vivienda)
    -- ================================================================
    ROUND(SUM(CASE 
        WHEN is_shared = TRUE AND movement_type IN ('EXPENSE', 'EXPENSE_REFUND') 
            THEN amount 
        ELSE 0.00 
    END), 2) AS household_total_cost,

    -- Cuota de hipoteca del hogar (100%)
    ROUND(SUM(CASE 
        WHEN category_id = 'FIX_HIPOTECA' 
            THEN amount 
        ELSE 0.00 
    END), 2) AS mortgage_household_amount

FROM tx
GROUP BY accrual_month
ORDER BY accrual_month DESC