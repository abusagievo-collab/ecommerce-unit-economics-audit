-- ============================================================================
-- Проект: Аудит юнит-экономики и поиск убыточных SKU в e-commerce
-- Описание: Дедупликация логов, учет возвратов и расчет Contribution Margin (CM1, CM2)
-- СУБД: PostgreSQL
-- ============================================================================

WITH deduplicated_orders AS (
    -- Шаг 1. Удаляем дубликаты транзакций из сырых логов по окну order_id
    SELECT
        order_id,
        user_id,
        sku_id,
        category_name,
        order_timestamp AT TIME ZONE 'UTC' AS order_ts_utc,
        gross_revenue,
        cogs,
        promo_discount,
        shipping_cost,
        is_returned,
        return_shipping_cost,
        ROW_NUMBER() OVER (
            PARTITION BY order_id, sku_id
            ORDER BY updated_at DESC
        ) AS rn
    FROM raw_transactions
    WHERE gross_revenue > 0
      AND user_id IS NOT NULL
),
clean_orders AS (
    SELECT *
    FROM deduplicated_orders
    WHERE rn = 1
),
sku_unit_economics AS (
    -- Шаг 2. Рассчитываем чистую выручку и маржинальность (CM2) с учетом возвратов
    SELECT
        sku_id,
        category_name,
        COUNT(order_id) AS total_orders,
        SUM(CASE WHEN is_returned THEN 1 ELSE 0 END) AS returned_orders,
        ROUND(
            100.0 * SUM(CASE WHEN is_returned THEN 1 ELSE 0 END) / NULLIF(COUNT(order_id), 0),
            2
        ) AS return_rate_pct,
        SUM(gross_revenue - promo_discount) AS gmv_after_discount,
        SUM(
            CASE
                WHEN is_returned THEN -(shipping_cost + return_shipping_cost)
                ELSE (gross_revenue - promo_discount - cogs - shipping_cost)
            END
        ) AS net_contribution_margin
    FROM clean_orders
    GROUP BY sku_id, category_name
)
-- Шаг 3. Выявляем убыточные SKU и считаем их долю в общем убытке через оконные функции
SELECT
    sku_id,
    category_name,
    total_orders,
    return_rate_pct,
    gmv_after_discount,
    net_contribution_margin,
    ROUND(
        100.0 * net_contribution_margin / NULLIF(gmv_after_discount, 0),
        2
    ) AS margin_pct,
    SUM(net_contribution_margin) OVER (PARTITION BY category_name) AS category_total_margin
FROM sku_unit_economics
WHERE total_orders >= 20
ORDER BY net_contribution_margin ASC;
