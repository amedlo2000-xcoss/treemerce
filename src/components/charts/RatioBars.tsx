import { labelForBucket } from "@/lib/domain/enums";
import type { DemographicsBucket } from "@/lib/domain/types";

const SMALL_BUCKET = "該当データ少数";

/**
 * 構成比の水平バーチャート。
 *
 * 「カテゴリ間の大小比較」= 単一ヒュー (sequential) を使う。1系列なので凡例は不要で、
 * 各バーに直接ラベル (件数と構成比) を添えるため、色だけに意味を持たせていない。
 * 「該当データ少数」は中立グレーで最後に固定し、実データのカテゴリと見間違えないようにする。
 */
export function RatioBars({
  title,
  dimension,
  buckets,
  emptyLabel = "対象データがありません",
}: {
  title: string;
  dimension: string;
  buckets: DemographicsBucket[];
  emptyLabel?: string;
}) {
  const max = buckets.reduce((acc, b) => Math.max(acc, b.count), 0);

  return (
    <section className="rounded-xl border border-zinc-200 bg-white p-5 dark:border-zinc-800 dark:bg-zinc-950">
      <h3 className="text-sm font-semibold text-zinc-900 dark:text-zinc-100">{title}</h3>

      {buckets.length === 0 ? (
        <p className="mt-4 text-xs text-zinc-500 dark:text-zinc-400">{emptyLabel}</p>
      ) : (
        <ul className="mt-4 space-y-3">
          {buckets.map((bucket) => {
            const isSmall = bucket.key === SMALL_BUCKET;
            const width = max > 0 ? Math.max((bucket.count / max) * 100, 1.5) : 0;
            const label = labelForBucket(dimension, bucket.key);

            return (
              <li key={bucket.key} className="group grid grid-cols-[7rem_1fr_5.5rem] items-center gap-3">
                <span
                  className="truncate text-xs text-zinc-600 dark:text-zinc-400"
                  title={label}
                >
                  {label}
                </span>

                <span
                  className="relative block h-2 rounded-full"
                  style={{ background: "var(--viz-track)" }}
                >
                  <span
                    className="absolute inset-y-0 left-0 rounded-full transition-[width]"
                    style={{
                      width: `${width}%`,
                      background: isSmall ? "var(--viz-series-muted)" : "var(--viz-series-1)",
                    }}
                  />
                  {/* ホバー時の詳細 */}
                  <span className="pointer-events-none absolute -top-8 left-0 z-10 hidden whitespace-nowrap rounded-md bg-zinc-900 px-2 py-1 text-[11px] font-medium text-white group-hover:block dark:bg-zinc-100 dark:text-zinc-900">
                    {label}: {bucket.count}件 ({bucket.ratio}%)
                  </span>
                </span>

                <span className="text-right text-xs tabular-nums text-zinc-700 dark:text-zinc-300">
                  {bucket.ratio}%
                  <span className="ml-1 text-zinc-400 dark:text-zinc-500">({bucket.count})</span>
                </span>
              </li>
            );
          })}
        </ul>
      )}
    </section>
  );
}
