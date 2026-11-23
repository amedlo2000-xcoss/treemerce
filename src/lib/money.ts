/**
 * 金額の表示単位と整形。
 *
 * このサイトは実際の円を扱わないサンプルとして見せるため、単位は「TWA」。
 * 画面に出す金額はすべて formatAmount() を通し、単位名は CURRENCY_UNIT だけで変えられるようにする。
 * DB の値 (orders.currency など) は変更しない。
 */
export const CURRENCY_UNIT = "TWA";

/** 10000 → "10,000 TWA"。null / undefined は "—"。 */
export function formatAmount(value: number | string | null | undefined): string {
  if (value == null || value === "") return "—";
  const n = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(n)) return "—";
  return `${new Intl.NumberFormat("ja-JP", { maximumFractionDigits: 0 }).format(n)} ${CURRENCY_UNIT}`;
}
