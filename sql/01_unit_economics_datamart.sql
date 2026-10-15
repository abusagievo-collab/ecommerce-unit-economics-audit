-- ============================================================================
-- Проект: Аудит юнит-экономики и поиск убыточных SKU в e-commerce (Рынок РК, KZT)
-- Описание: Дедупликация логов, учет возвратов и расчет Contribution Margin (CM2)
-- СУБД: PostgreSQL
-- ============================================================================

WITH deduplicated_orders AS (
    SELECT
        order_id,
        user_id,
        sku_id,
        category_name,
        city_name,
        order_timestamp AT TIME ZONE 'Asia/Almaty' AS order_ts_almaty,
        gross_revenue_kzt,
        cogs_kzt,
        promo_discount_kzt,
        shipping_cost_kzt,
        is_returned,
        return_shipping_cost_kzt,
        ROW_NUMBER() OVER (
            PARTITION BY order_id, sku_id
            ORDER BY updated_at DESC
        ) AS rn
    FROM raw_transactions
    WHERE gross_revenue_kzt > 0
      AND user_id IS NOT NULL
),
clean_orders AS (
    SELECT *
    FROM deduplicated_orders
    WHERE rn = 1
),
sku_unit_economics AS (
    SELECT
        sku_id,
        category_name,
        city_name,
        COUNT(order_id) AS total_orders,
        SUM(CASE WHEN is_returned THEN 1 ELSE 0 END) AS returned_orders,
        ROUND(
            100.0 * SUM(CASE WHEN is_returned THEN 1 ELSE 0 END) / NULLIF(COUNT(order_id), 0),
            2
        ) AS return_rate_pct,
        SUM(gross_revenue_kzt - promo_discount_kzt) AS gmv_after_discount_kzt,
        SUM(
            CASE
                WHEN is_returned THEN -(shipping_cost_kzt + return_shipping_cost_kzt)
                ELSE (gross_revenue_kzt - promo_discount_kzt - cogs_kzt - shipping_cost_kzt)
            END
        ) AS net_contribution_margin_kzt
    FROM clean_orders
    GROUP BY sku_id, category_name, city_name
)
SELECT
    sku_id,
    category_name,
    city_name,
    total_orders,
    return_rate_pct,
    gmv_after_discount_kzt,
    net_contribution_margin_kzt,
    ROUND(
        100.0 * net_contribution_margin_kzt / NULLIF(gmv_after_discount_kzt, 0),
        2
    ) AS margin_pct,
    SUM(net_contribution_margin_kzt) OVER (PARTITION BY category_name) AS category_total_margin_kzt
FROM sku_unit_economics
WHERE total_orders >= 20
ORDER BY net_contribution_margin_kzt ASC;
