import Link from "next/link";

import { Card, EmptyState, PageHeader, formatDateTime } from "@/components/ui";
import { requireSuperAdminPage } from "@/lib/auth/viewer";
import type { ShopSettingsRow } from "@/lib/domain/types";

import { ShopSettingsForm } from "./ShopSettingsForm";

/** ショップ設定 (super_admin 専用): 注文受付・送料・支払期限・運営の振込先・特商法表記。 */
export default async function AdminShopSettingsPage() {
  const { supabase } = await requireSuperAdminPage("/admin/settings");

  const { data } = await supabase.from("shop_settings").select("*").eq("id", 1).maybeSingle();
  const settings = data as ShopSettingsRow | null;

  return (
    <>
      <PageHeader
        title="ショップ設定"
        description="注文受付の開始・停止、送料、支払期限、お振込先、特定商取引法に基づく表記を管理します。"
        action={
          <Link href="/legal/tokushoho" target="_blank" className="text-[13px] font-semibold text-brand hover:underline">
            特商法ページを確認
          </Link>
        }
      />
      {settings ? (
        <Card title="設定内容" description={`最終更新: ${formatDateTime(settings.updated_at)}`}>
          <ShopSettingsForm key={settings.updated_at} settings={settings} />
        </Card>
      ) : (
        <EmptyState title="ショップ設定を読み込めませんでした" description="migration 0010 が適用されているか確認してください。" />
      )}
    </>
  );
}
