"""
Модуль автоматической очистки транзакционных логов и расчета юнит-экономики (в KZT).
"""

import re
import numpy as np
import pandas as pd


def clean_transaction_logs(df: pd.DataFrame) -> pd.DataFrame:
    """
    Очищает сырой датафрейм заказов от дубликатов, аномалий доставки и битых строк.
    Все финансовые показатели рассчитываются в тенге (KZT).
    """
    data = df.copy()

    # 1. Стандартизация промокодов (удаление лишних пробелов и спецсимволов)
    if "promo_code" in data.columns:
        data["promo_code"] = (
            data["promo_code"]
            .fillna("NO_PROMO")
            .astype(str)
            .apply(lambda x: re.sub(r"[^A-Z0-9_]", "", x.strip().upper()))
        )

    # 2. Удаление дубликатов по связке (order_id, sku_id)
    data = data.sort_values("order_timestamp").drop_duplicates(
        subset=["order_id", "sku_id"], keep="last"
    )

    # 3. Удаление записей без user_id и с некорректной суммой чека
    data = data.dropna(subset=["user_id", "gross_revenue_kzt"])
    data = data[data["gross_revenue_kzt"] > 0]

    # 4. Обработка выбросов в стоимости доставки (KZT) методом межквартильного размаха (IQR)
    q1 = data["shipping_cost_kzt"].quantile(0.25)
    q3 = data["shipping_cost_kzt"].quantile(0.75)
    iqr = q3 - q1
    upper_bound = q3 + 1.5 * iqr
    data["shipping_cost_kzt"] = np.where(
        data["shipping_cost_kzt"] > upper_bound, upper_bound, data["shipping_cost_kzt"]
    )

    # 5. Расчет чистой операционной маржи заказа (Contribution Margin 2, KZT)
    data["net_margin_kzt"] = np.where(
        data["is_returned"] == 1,
        -(data["shipping_cost_kzt"] + data["return_shipping_cost_kzt"]),
        data["gross_revenue_kzt"]
        - data["promo_discount_kzt"]
        - data["cogs_kzt"]
        - data["shipping_cost_kzt"],
    )

    return data


if __name__ == "__main__":
    sample_df = pd.read_csv("data/processed/sample_orders_cleaned.csv")
    cleaned = clean_transaction_logs(sample_df)
    print(f"Обработано заказов: {len(cleaned)}")
    print(f"Итоговая чистая маржа: {cleaned['net_margin_kzt'].sum():,.0f} ₸ (KZT)")
