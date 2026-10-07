import { failFromPostgrest, ok, requireSuperAdminApi } from "@/lib/api/http";

/**
 * 発送依頼を「手動で依頼済み」として記録する (super_admin 専用)。
 * 発送依頼書をコピーして生産者へ連絡した後に使う。メール自動送信 (STEP6) は未実装。
 * 送り先・本文は保存しない。記録は監査ログにも残る (DB 側 / 0015)。
 */
export async function POST(_request: Request, context: { params: Promise<{ shipmentId: string }> }) {
  const guard = await requireSuperAdminApi();
  if ("error" in guard) return guard.error;

  const { shipmentId } = await context.params;
  const { data, error } = await guard.ctx.supabase.rpc("treemerce_admin_record_shipment_request", {
    p_shipment_id: shipmentId,
    p_channel: "manual",
  });
  if (error) return failFromPostgrest(error);

  return ok(data);
}
