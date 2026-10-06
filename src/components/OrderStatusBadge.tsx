import { Badge } from "@/components/ui";
import { ORDER_STATUS_LABELS } from "@/lib/domain/enums";

const TONE: Record<string, "amber" | "blue" | "green" | "neutral" | "red"> = {
  received: "amber",
  payment_confirmed: "blue",
  shipped: "blue",
  completed: "green",
  cancelled: "neutral",
};

export function OrderStatusBadge({ status }: { status: string }) {
  return <Badge tone={TONE[status] ?? "neutral"}>{ORDER_STATUS_LABELS[status] ?? status}</Badge>;
}
