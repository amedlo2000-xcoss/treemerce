import type { ShipmentRequest } from "@/lib/domain/types";

/**
 * 発送依頼書のテキスト (生産者へコピーして送る / STEP6 のメール本文にも使う)。
 * 含めるのは「その生産者の分」の注文番号・お届け先・商品・数量と、
 * 送り状の依頼主 (販売者 = 運営) だけ。代理店の情報・顧客のメールアドレス・販売価格は含めない。
 */
export function formatShipmentRequest(req: ShipmentRequest): string {
  const lines: string[] = [];
  const sender = req.sender;

  lines.push(`${req.producer.name} 御中`);
  lines.push("");
  lines.push("いつもお世話になっております。");
  lines.push("下記のご注文について、お客様への直接発送をお願いいたします。");
  lines.push("");
  lines.push("■ 注文番号");
  lines.push(req.order_no);
  if (req.producer.ship_lead_time) {
    lines.push("");
    lines.push("■ 発送目安");
    lines.push(req.producer.ship_lead_time);
  }
  lines.push("");
  lines.push("■ お届け先");
  lines.push(`${req.ship_to.name} 様`);
  if (req.ship_to.postal_code) lines.push(`〒${req.ship_to.postal_code}`);
  lines.push(req.ship_to.address);
  if (req.ship_to.phone) lines.push(`TEL: ${req.ship_to.phone}`);
  lines.push("");
  lines.push("■ 商品・数量");
  for (const item of req.items) {
    const spec = item.content_volume ? ` (${item.content_volume})` : "";
    const sku = item.product_sku ? ` [${item.product_sku}]` : "";
    lines.push(`・${item.product_name}${spec}${sku} × ${item.quantity}`);
  }
  if (req.customer_note) {
    lines.push("");
    lines.push("■ お客様からの備考");
    lines.push(req.customer_note);
  }
  lines.push("");
  lines.push("■ 送り状の依頼主 (ご依頼主欄には下記をご記入ください)");
  lines.push(sender.name ?? "(販売者名未設定)");
  if (sender.address) lines.push(sender.address);
  if (sender.phone) lines.push(`TEL: ${sender.phone}`);
  lines.push("");
  lines.push("発送後、発送日・配送業者・送り状番号をご連絡ください。");
  if (sender.name || sender.email || sender.phone) {
    lines.push("");
    lines.push("――――――――――");
    if (sender.name) lines.push(sender.name);
    if (sender.email) lines.push(sender.email);
    if (sender.phone) lines.push(`TEL: ${sender.phone}`);
  }
  return lines.join("\n");
}
