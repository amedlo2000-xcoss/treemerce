import { Lock } from "lucide-react";

import { MobilePageHeader, Surface } from "@/components/mobile/primitives";
import { BackLink, formatDateTime } from "@/components/ui";
import { requireAgentPage } from "@/lib/auth/viewer";
import type { AgentProfile } from "@/lib/domain/types";

import { AgentProfileForm } from "./AgentProfileForm";

/**
 * 事業プロフィールの編集 (本人のみ)。
 * プロフィールは本人と運営 (super_admin) にだけ見え、招待元・傘下などの他の代理店や、
 * 商流マップ・コミュニティマップには表示されない (0016)。
 */
export default async function AgentProfileEditPage() {
  const { supabase } = await requireAgentPage("/agent/my/profile");

  const { data, error } = await supabase.rpc("treemerce_my_agent_profile");
  if (error) throw new Error("プロフィールを読み込めませんでした。");
  const profile = data as AgentProfile;

  return (
    <>
      <BackLink href="/agent/my">MY</BackLink>
      <MobilePageHeader
        title="事業プロフィール"
        description="お仕事の内容や扱いたい商品を入力してください。商品の持込みのご相談に使います。"
      />

      <div className="flex items-start gap-2.5 rounded-2xl bg-surface-muted px-3.5 py-3">
        <Lock size={14} className="mt-0.5 shrink-0 text-text-secondary" />
        <p className="text-[12px] leading-5 text-text-secondary">
          このプロフィールは、あなたと運営だけが見られます。招待元や傘下の代理店など、ほかの代理店には表示されません。
        </p>
      </div>

      {profile.updated_by_role === "super_admin" ? (
        <p className="rounded-2xl bg-brand-soft px-3.5 py-3 text-[13px] leading-5 text-text-primary">
          {formatDateTime(profile.updated_at)} に、あなたから伺った内容をもとに運営が更新しました。
          内容に違いがあれば、このページで直して保存してください。
        </p>
      ) : null}

      <Surface>
        <AgentProfileForm profile={profile} />
      </Surface>
    </>
  );
}
