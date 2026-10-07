import type { SupabaseClient } from "@supabase/supabase-js";

import type { ProducerPublicRow } from "@/lib/domain/types";

/**
 * 商品フォームの生産者の選択肢。公開項目の列だけを読む
 * (連絡先・送り先メールは列 GRANT が無く、ここでは取得できない)。
 * 仮の生産者を先頭に、有効な生産者を名前順に。現在の生産者が無効ならそれも残す。
 */
export async function loadProducerOptions(
  supabase: SupabaseClient,
  currentProducerId: string | null = null,
): Promise<ProducerPublicRow[]> {
  const { data } = await supabase
    .from("producers")
    .select("id, name, origin, ship_from_prefecture, ship_lead_time, is_active, is_placeholder")
    .order("is_placeholder", { ascending: false })
    .order("name", { ascending: true });

  return ((data ?? []) as ProducerPublicRow[]).filter(
    (p) => p.is_active || p.id === currentProducerId,
  );
}
