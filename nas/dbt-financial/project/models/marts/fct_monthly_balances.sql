{{ config(
    tags = ['mart', 'finance', 'balances']
) }}

WITH ranked_tx AS (
    SELECT
        account_id,
        bank,
        account_type,
        account_ownership,
        DATE_TRUNC('month', value_date)::DATE AS year_month,
        value_date,
        balance,
        ROW_NUMBER() OVER (
            PARTITION BY account_id, DATE_TRUNC('month', value_date)
            ORDER BY value_date DESC, source_row_id DESC
        ) AS rank_last_in_month
    FROM {{ ref('fct_transactions') }}
    WHERE balance IS NOT NULL
)

SELECT
    year_month,
    account_id,
    bank,
    account_type,
    account_ownership,
    ROUND(balance, 2) AS closing_balance
FROM ranked_tx
WHERE rank_last_in_month = 1
ORDER BY year_month DESC, account_id