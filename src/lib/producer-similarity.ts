/**
 * 持込み申請の承認画面で「似た名前の既存生産者」を候補に出すための簡易判定。
 * 候補を示すだけで、同一かどうかは super_admin が産地・発送元を見て判断する
 * (自動でひも付けることはしない)。
 */

const CORPORATE_FORMS = /株式会社|有限会社|合同会社|合資会社|一般社団法人|農事組合法人|\(株\)|\(有\)|\(同\)|㈱|㈲/g;
const NOISE = /[\s・･\-‐−ー_.,，、。()（）「」『』【】]/g;

export function normalizeProducerName(name: string): string {
  return name.normalize("NFKC").toLowerCase().replace(CORPORATE_FORMS, "").replace(NOISE, "");
}

function bigrams(value: string): string[] {
  if (value.length < 2) return value ? [value] : [];
  const result: string[] = [];
  for (let i = 0; i < value.length - 1; i += 1) result.push(value.slice(i, i + 2));
  return result;
}

/** 0〜1 の類似度 (文字 bigram の Dice 係数。片方がもう片方を含む場合は 0.9 以上) */
export function producerNameSimilarity(a: string, b: string): number {
  const x = normalizeProducerName(a);
  const y = normalizeProducerName(b);
  if (!x || !y) return 0;
  if (x === y) return 1;
  if (Math.min(x.length, y.length) >= 2 && (x.includes(y) || y.includes(x))) return 0.9;

  const bx = bigrams(x);
  const by = bigrams(y);
  const counts = new Map<string, number>();
  for (const g of by) counts.set(g, (counts.get(g) ?? 0) + 1);
  let overlap = 0;
  for (const g of bx) {
    const n = counts.get(g) ?? 0;
    if (n > 0) {
      overlap += 1;
      counts.set(g, n - 1);
    }
  }
  return (2 * overlap) / (bx.length + by.length);
}

export const SIMILARITY_THRESHOLD = 0.5;

/** 似た名前の候補 (類似度の高い順、最大 limit 件) */
export function findSimilarProducers<T extends { name: string }>(
  name: string | null,
  producers: T[],
  limit = 5,
): (T & { similarity: number })[] {
  if (!name) return [];
  return producers
    .map((p) => ({ ...p, similarity: producerNameSimilarity(name, p.name) }))
    .filter((p) => p.similarity >= SIMILARITY_THRESHOLD)
    .sort((a, b) => b.similarity - a.similarity)
    .slice(0, limit);
}
