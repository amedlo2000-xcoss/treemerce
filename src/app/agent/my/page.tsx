import {
  BarChart3,
  Briefcase,
  ChevronRight,
  GitBranch,
  Lock,
  PackagePlus,
  Settings,
  ShoppingBag,
  TrendingUp,
  UserPlus,
} from "lucide-react";
import type { LucideIcon } from "lucide-react";
import Link from "next/link";

import {
  InfoRow,
  MobilePageHeader,
  PrimaryButton,
  ProfileHero,
  SectionLabel,
  StatTile,
  StatusPill,
  Surface,
} from "@/components/mobile/primitives";
import { FormMessage, formatDate } from "@/components/ui";
import { signOutAction } from "@/app/actions";
import { requireAgentPage } from "@/lib/auth/viewer";
import { AGENT_INDUSTRY_LABELS, AGENT_STATUS_LABELS } from "@/lib/domain/enums";
import type { AgentProfile, BankAccountRow } from "@/lib/domain/types";

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
 * 事業プロフィール (0016) は本人用 RPC からのみ取得する (本人と super_admin だけが見られる)。
 */
export default async function AgentMyPage({
  searchParams,
}: {
  searchParams: Promise<{ profile?: string }>;
}) {
  const { profile: profileFlag } = await searchParams;
  const { supabase, agent } = await requireAgentPage("/agent/my");

  const { data: profileData } = await supabase.rpc("treemerce_my_agent_profile");
  const profile = (profileData as AgentProfile | null) ?? null;

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

      <div className="space-y-5 md:grid md:grid-cols-2 md:items-start md:gap-6 md:space-y-0">
        <div className="space-y-5">
          <ProfileHero
            name={agent.display_name}
            subtitle={agent.public_id}
            mono
            pills={
              <StatusPill tone={STATUS_TONE[agent.status]}>
                {AGENT_STATUS_LABELS[agent.status]}
              </StatusPill>
            }
            meta={
              <div className="grid grid-cols-2 gap-2">
                <StatTile label="登録日" value={formatDate(agent.registered_at)} />
                <StatTile label="都道府県" value={agent.prefecture ?? "—"} />
              </div>
            }
          />

          <div className="space-y-2">
            <SectionLabel>登録経路</SectionLabel>
            <Surface>
              <div className="flex items-center gap-3">
                <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-2xl bg-brand-soft text-brand">
                  <GitBranch size={18} />
                </div>
                <dl className="min-w-0 flex-1">
                  <dt className="text-[12px] text-text-secondary">招待元の代理店</dt>
                  <dd className="truncate text-[15px] font-semibold text-text-primary">
                    {agent.invited_by ? (inviterName ?? "代理店招待URL経由") : "招待元なし"}
                  </dd>
                </dl>
              </div>
              <div className="mt-3 flex items-start gap-2.5 rounded-2xl bg-surface-muted px-3 py-2.5">
                <Lock size={14} className="mt-0.5 shrink-0 text-text-secondary" />
                <p className="text-[12px] leading-5 text-text-secondary">
                  登録経路は登録時に確定し、以後変更されません。商品購入者の担当とは別の情報です。
                </p>
              </div>
            </Surface>
          </div>

          <div className="space-y-2">
            <SectionLabel>事業プロフィール</SectionLabel>
            {profileFlag === "saved" ? (
              <FormMessage tone="success">事業プロフィールを保存しました。</FormMessage>
            ) : null}
            <Surface>
              <div className="flex items-center gap-3">
                <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-2xl bg-brand-soft text-brand">
                  <Briefcase size={18} />
                </div>
                <dl className="min-w-0 flex-1">
                  <dt className="text-[12px] text-text-secondary">業種</dt>
                  <dd className="truncate text-[15px] font-semibold text-text-primary">
                    {profile?.industry
                      ? (AGENT_INDUSTRY_LABELS[profile.industry] ?? profile.industry)
                      : "未入力"}
                  </dd>
                </dl>
              </div>
              {profile?.offerings ? (
                <p className="mt-3 line-clamp-3 whitespace-pre-wrap text-[13px] leading-5 text-text-secondary">
                  {profile.offerings}
                </p>
              ) : (
                <p className="mt-3 text-[13px] leading-5 text-text-secondary">
                  お仕事の内容や売りたい物を入力すると、商品の持込みの相談がスムーズになります。
                </p>
              )}
              <div className="mt-3 flex items-start gap-2.5 rounded-2xl bg-surface-muted px-3 py-2.5">
                <Lock size={14} className="mt-0.5 shrink-0 text-text-secondary" />
                <p className="text-[12px] leading-5 text-text-secondary">
                  あなたと運営だけが見られます。ほかの代理店には表示されません。
                </p>
              </div>
              <div className="mt-3">
                <PrimaryButton href="/agent/my/profile" variant="secondary">
                  {profile?.found ? "事業プロフィールを編集" : "事業プロフィールを入力"}
                </PrimaryButton>
              </div>
            </Surface>
          </div>

          <div className="space-y-2">
            <SectionLabel>アカウント</SectionLabel>
            <Surface className="!py-1">
              <dl className="divide-y divide-border-soft">
                <InfoRow label="メール" value={agent.email} />
                <InfoRow label="電話番号" value={agent.phone ?? "—"} />
              </dl>
            </Surface>
          </div>

          <Surface padded={false} className="divide-y divide-border-soft px-3">
            <LinkRow icon={UserPlus} label="招待URL・ショップの紹介リンク" href="/agent/invitations" />
            <LinkRow icon={PackagePlus} label="商品の持込み申請" href="/agent/submissions" />
            <LinkRow icon={TrendingUp} label="持込み商品の売れ行き" href="/agent/sourced-sales" />
            <LinkRow icon={ShoppingBag} label="担当顧客の注文" href="/agent/orders" />
            <LinkRow icon={BarChart3} label="客層分析" href="/agent/analytics" />
            <div className="flex items-center gap-3 px-2 py-3.5 opacity-50">
              <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-surface-muted text-text-secondary">
                <Settings size={18} strokeWidth={1.8} />
              </div>
              <span className="flex-1 text-[15px] font-medium text-text-primary">アカウント設定</span>
              <span className="text-[12px] text-text-secondary">準備中</span>
            </div>
          </Surface>

          <form action={signOutAction} className="md:hidden">
            <PrimaryButton type="submit" variant="secondary">
              ログアウト
            </PrimaryButton>
          </form>
        </div>

        <div className="space-y-5">
          <SectionLabel>口座情報</SectionLabel>
          <Surface>
            <BankAccountForm
              agentId={agent.id}
              account={(bankAccount as BankAccountRow | null) ?? null}
            />
          </Surface>

          <form action={signOutAction} className="hidden md:block">
            <PrimaryButton type="submit" variant="secondary">
              ログアウト
            </PrimaryButton>
          </form>
        </div>
      </div>
    </>
  );
}
