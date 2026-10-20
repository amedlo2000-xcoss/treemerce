/**
 * IP アドレスごとの簡易な回数制限 (固定時間内の試行回数)。
 *
 * サーバーのメモリに記録するため、同じサーバーインスタンスに届いた試行だけを数える
 * (Vercel では温まったインスタンスが再利用されるので連続の申し込みは概ね同じインスタンスに届くが、
 *  インスタンスをまたぐ厳密な制限ではない)。DB や外部ストアに記録する方式へ置き換える前提の最低限の防御。
 */
type Bucket = { hits: number[] };

const buckets = new Map<string, Bucket>();
const MAX_KEYS = 10_000;

export function takeRateLimit(key: string, limit: number, windowMs: number): { ok: boolean; retryAfterSec: number } {
  const now = Date.now();
  const bucket = buckets.get(key) ?? { hits: [] };
  bucket.hits = bucket.hits.filter((t) => now - t < windowMs);

  if (bucket.hits.length >= limit) {
    buckets.set(key, bucket);
    return { ok: false, retryAfterSec: Math.max(1, Math.ceil((bucket.hits[0] + windowMs - now) / 1000)) };
  }

  bucket.hits.push(now);
  buckets.set(key, bucket);

  // メモリを使い続けないよう、古い記録を捨てる
  if (buckets.size > MAX_KEYS) {
    for (const [k, b] of buckets) {
      if (b.hits.every((t) => now - t >= windowMs)) buckets.delete(k);
    }
  }
  return { ok: true, retryAfterSec: 0 };
}
