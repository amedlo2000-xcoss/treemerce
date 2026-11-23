/**
 * 日時の表示はすべて日本時間 (Asia/Tokyo) で行う。
 * サーバー (Vercel) は UTC で動くため、タイムゾーンを指定しない Intl / toLocale* は使わず、
 * 画面に出す日時は必ずこのファイルの関数を通す。
 */
export const TIME_ZONE = "Asia/Tokyo";

type DateInput = string | number | Date | null | undefined;

/** "YYYY-MM-DD" (日付だけの値) は日本時間のその日として扱う */
function toDate(value: DateInput): Date | null {
  if (value == null || value === "") return null;
  if (value instanceof Date) return Number.isNaN(value.getTime()) ? null : value;
  if (typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value)) {
    return new Date(`${value}T00:00:00+09:00`);
  }
  const d = new Date(value);
  return Number.isNaN(d.getTime()) ? null : d;
}

function format(value: DateInput, options: Intl.DateTimeFormatOptions): string {
  const d = toDate(value);
  if (!d) return "—";
  return new Intl.DateTimeFormat("ja-JP", { timeZone: TIME_ZONE, ...options }).format(d);
}

/** 2026/11/23 */
export function formatDate(value: DateInput): string {
  return format(value, { year: "numeric", month: "2-digit", day: "2-digit" });
}

/** 2026/11/23 15:48 */
export function formatDateTime(value: DateInput): string {
  return format(value, { year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit" });
}

/** 2026年11月23日(月) */
export function formatLongDate(value: DateInput): string {
  return format(value, { year: "numeric", month: "long", day: "numeric", weekday: "short" });
}

/** 2026年11月 */
export function formatYearMonth(value: DateInput): string {
  return format(value, { year: "numeric", month: "short" });
}

/** 日本時間の今日 "YYYY-MM-DD" */
export function todayInTokyo(now: Date = new Date()): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: TIME_ZONE }).format(now);
}

/** 日本時間の今月 1 日 0:00 (ISO 文字列) */
export function startOfMonthInTokyo(now: Date = new Date()): string {
  const [y, m] = todayInTokyo(now).split("-");
  return new Date(`${y}-${m}-01T00:00:00+09:00`).toISOString();
}
