{{ config(
    tags = ['mart', 'finance', 'pnl']
) }}

WITH tx AS (
    SELECT * FROM {{ ref('fct_transactions') }}
),

monthly_pnl AS (
    SELECT
        accrual_month AS year_month,
        EXTRACT(YEAR FROM accrual_month)::INT AS year,
        EXTRACT(MONTH FROM accrual_month)::INT AS month,

        -- ================================================================
        -- 1. P&L PERSONAL (personal_amount)
        -- ================================================================
        ROUND(SUM(CASE 
            WHEN is_pnl = TRUE AND movement_type = 'INCOME' 
                THEN personal_amount 
            ELSE 0.00 
        END), 2) AS personal_income,

        ROUND(SUM(CASE 
            WHEN is_pnl = TRUE AND movement_type IN ('EXPENSE', 'EXPENSE_REFUND') 
                THEN personal_amount 
            ELSE 0.00 
        END), 2) AS personal_expense,

        ROUND(SUM(CASE 
            WHEN is_pnl = TRUE AND group_name IN ('Gastos Fijos', 'Gastos Compartidos') 
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

        ROUND(SUM(CASE 
            WHEN is_pnl = TRUE 
                THEN personal_amount 
            ELSE 0.00 
        END), 2) AS personal_net_savings,

        CASE
            WHEN SUM(CASE WHEN is_pnl = TRUE AND movement_type = 'INCOME' THEN personal_amount ELSE 0.00 END) > 0
            THEN ROUND(
                (
                    SUM(CASE WHEN is_pnl = TRUE THEN personal_amount ELSE 0.00 END)
                    / SUM(CASE WHEN is_pnl = TRUE AND movement_type = 'INCOME' THEN personal_amount ELSE 0.00 END)
                ), 
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

        ROUND(SUM(CASE 
            WHEN category_id = 'FIX_HIPOTECA' 
                THEN amount 
            ELSE 0.00 
        END), 2) AS mortgage_household_amount

    FROM tx
    GROUP BY accrual_month
),

with_mom_metrics AS (
    SELECT
        *,

        -- Valores del mes anterior (LAG ordenado cronológicamente ascendente)
        LAG(personal_income, 1) OVER (ORDER BY year_month ASC) AS prev_personal_income,
        LAG(personal_expense, 1) OVER (ORDER BY year_month ASC) AS prev_personal_expense,
        LAG(personal_net_savings, 1) OVER (ORDER BY year_month ASC) AS prev_personal_net_savings,
        LAG(savings_rate_pct, 1) OVER (ORDER BY year_month ASC) AS prev_savings_rate_pct,
        LAG(household_total_cost, 1) OVER (ORDER BY year_month ASC) AS prev_household_total_cost,

        -- Variaciones porcentuales intermensuales (MoM %)
        -- 1. Ingresos
        ROUND(
            ((personal_income - LAG(personal_income, 1) OVER (ORDER BY year_month ASC)) 
            / NULLIF(LAG(personal_income, 1) OVER (ORDER BY year_month ASC), 0)),
            2
        ) AS personal_income_mom_pct,

        -- 2. Gastos personales (al ser negativos, se evalúa la variación de magnitud absoluta)
        ROUND(
            ((ABS(personal_expense) - ABS(LAG(personal_expense, 1) OVER (ORDER BY year_month ASC))) 
            / NULLIF(ABS(LAG(personal_expense, 1) OVER (ORDER BY year_month ASC)), 0)),
            2
        ) AS personal_expense_mom_pct,

        -- 3. Coste total del hogar
        ROUND(
            ((ABS(household_total_cost) - ABS(LAG(household_total_cost, 1) OVER (ORDER BY year_month ASC))) 
            / NULLIF(ABS(LAG(household_total_cost, 1) OVER (ORDER BY year_month ASC)), 0)),
            2
        ) AS household_cost_mom_pct

    FROM monthly_pnl
)

SELECT * FROM with_mom_metrics
ORDER BY year_month DESC