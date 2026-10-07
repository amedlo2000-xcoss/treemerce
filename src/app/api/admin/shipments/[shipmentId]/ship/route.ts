import { fail, failFromPostgrest, ok, readJson, requireSuperAdminApi } from "@/lib/api/http";

type Body = {
  shipped_on?: string;
  carrier?: string | null;
  tracking_number?: string | null;
  reason?: string | null;
};

const DATE = /^\d{4}-\d{2}-\d{2}$/;

/**
 * 生産者ごとの発送登録・訂正 (super_admin 専用)。
 * 状態の検証・未来日の拒否・訂正時の理由必須・監査ログ・全発送完了時の注文の
 * 「発送済み」への自動変更は、すべて DB 側 (treemerce_admin_ship_shipment / 0015) で強制される。
 */
export async function POST(request: Request, context: { params: Promise<{ shipmentId: string }> }) {
  const guard = await requireSuperAdminApi();
  if ("error" in guard) return guard.error;

  const { shipmentId } = await context.params;
  const body = await readJson<Body>(request);
  if (!body?.shipped_on || !DATE.test(body.shipped_on)) {
    return fail("TREEMERCE_INVALID_INPUT", "発送日を指定してください。", 400);
  }

  const text = (v: unknown) => (typeof v === "string" && v.trim() ? v.trim() : null);

  const { data, error } = await guard.ctx.supabase.rpc("treemerce_admin_ship_shipment", {
    p_shipment_id: shipmentId,
    p_shipped_on: body.shipped_on,
    p_carrier: text(body.carrier),
    p_tracking_number: text(body.tracking_number),
    p_reason: text(body.reason),
  });
  if (error) return failFromPostgrest(error);

  return ok(data);
}
