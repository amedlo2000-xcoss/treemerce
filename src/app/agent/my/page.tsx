import { BarChart3, ChevronRight, Settings, UserCircle, UserPlus } from "lucide-react";
import type { LucideIcon } from "lucide-react";
import Link from "next/link";

import { PrimaryButton, SectionLabel, StatusPill, Surface, MobilePageHeader } from "@/components/mobile/primitives";
import { formatDate } from "@/components/ui";
import { signOutAction } from "@/app/actions";
import { requireAgentPage } from "@/lib/auth/viewer";
import { AGENT_STATUS_LABELS } from "@/lib/domain/enums";
import type { BankAccountRow } from "@/lib/domain/types";

import { BankAccountForm } from "./BankAccountForm";

const STATUS_TONE = {
  active: "success",
  pending: "warning",
  suspended: "danger",
  withdrawn: "neutral",
} as const;

function LinkRow({
  icon: Icon,
  label,
  href,
}: {
  icon: LucideIcon;
  label: string;
  href: string;
}) {
  return (
    <Link
      href={href}
      className="flex items-center gap-3 rounded-2xl px-2 py-3.5 transition-colors hover:bg-surface-muted"
    >
      <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-surface-muted text-text-secondary">
        <Icon size={18} strokeWidth={1.8} />
      </div>
      <span className="flex-1 text-[15px] font-medium text-text-primary">{label}</span>
      <ChevronRight size={18} className="text-text-secondary" />
    </Link>
  );
}

/**
 * MYページ (STEP9): プロフィール・登録経路(閲覧のみ)・各種メニューへの入口をまとめる。
 * 「招待元」は登録経路を示すだけで、担当顧客とは無関係 (絶対原則3)。
 */
export default async function AgentMyPage() {
  const { supabase, agent } = await requireAgentPage("/agent/my");

  let inviterName: string | null = null;
  if (agent.invited_by) {
    // 0006: 自分の招待元だけを解決する読み取り専用 RPC。未適用環境でも落ちないようフォールバックする。
    const { data } = await supabase.rpc("treemerce_my_inviter_profile");
    const profile = data as { found?: boolean; display_name?: string } | null;
    if (profile?.found) inviterName = profile.display_name ?? null;
  }

  const { data: bankAccount } = await supabase
    .from("bank_accounts")
    .select("*")
    .eq("agent_id", agent.id)
    .maybeSingle();

  return (
    <>
      <MobilePageHeader title="MY" />

      <Surface className="flex items-center gap-4">
        <div className="flex h-16 w-16 shrink-0 items-center justify-center rounded-full bg-brand-soft text-brand">
          <UserCircle size={34} strokeWidth={1.6} />
        </div>
        <div className="min-w-0 flex-1">
          <p className="truncate text-[19px] font-bold text-text-primary">{agent.display_name}</p>
          <p className="font-mono text-[12px] text-text-secondary">{agent.public_id}</p>
          <div className="mt-1.5">
            <StatusPill tone={STATUS_TONE[agent.status]}>
              {AGENT_STATUS_LABELS[agent.status]}
            </StatusPill>
          </div>
        </div>
      </Surface>

      <Surface>
        <dl className="divide-y divide-border-soft">
          <div className="flex items-center justify-between py-2.5">
            <dt className="text-[13px] text-text-secondary">登録日</dt>
            <dd className="text-[14px] font-medium text-text-primary">
              {formatDate(agent.registered_at)}
            </dd>
          </div>
          <div className="flex items-center justify-between py-2.5">
            <dt className="text-[13px] text-text-secondary">招待元</dt>
            <dd className="text-[14px] font-medium text-text-primary">
              {agent.invited_by ? (inviterName ?? "代理店招待URL経由") : "招待元なし"}
            </dd>
          </div>
        </dl>
        <p className="mt-2 text-[12px] leading-5 text-text-secondary">
          登録経路は登録時に確定し、以後変更されません。商品購入者の担当とは別の情報です。
        </p>
      </Surface>

      <Surface padded={false} className="divide-y divide-border-soft px-3">
        <LinkRow icon={UserPlus} label="招待URLの発行・履歴" href="/agent/invitations" />
        <LinkRow icon={BarChart3} label="客層分析" href="/agent/analytics" />
        <div className="flex items-center gap-3 px-2 py-3.5 opacity-50">
          <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-surface-muted text-text-secondary">
            <Settings size={18} strokeWidth={1.8} />
          </div>
          <span className="flex-1 text-[15px] font-medium text-text-primary">アカウント設定</span>
          <span className="text-[12px] text-text-secondary">準備中</span>
        </div>
      </Surface>

      <SectionLabel>口座情報</SectionLabel>
      <Surface>
        <BankAccountForm agentId={agent.id} account={(bankAccount as BankAccountRow | null) ?? null} />
      </Surface>

      <form action={signOutAction}>
        <PrimaryButton type="submit" variant="secondary">
          ログアウト
        </PrimaryButton>
      </form>
    </>
  );
}
