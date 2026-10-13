import type { SupabaseClient } from "@supabase/supabase-js";

import type { AdminCategoryRow, CatalogCategory } from "@/lib/domain/types";

/**
 * 商品カテゴリのマスタ (0022)。カテゴリ名はコードに持たず、常に DB から読む。
 *   公開 (有効なもの・並び順)        : treemerce_catalog_categories
 *   super_admin (無効を含む・使用中) : treemerce_admin_list_categories
 */
export async function loadCatalogCategories(supabase: SupabaseClient): Promise<CatalogCategory[]> {
  const { data } = await supabase.rpc("treemerce_catalog_categories");
  return (data ?? []) as CatalogCategory[];
}

export async function loadAdminCategories(supabase: SupabaseClient): Promise<AdminCategoryRow[]> {
  const { data, error } = await supabase.rpc("treemerce_admin_list_categories");
  if (error) throw new Error("カテゴリを読み込めませんでした。");
  return (data ?? []) as AdminCategoryRow[];
}
