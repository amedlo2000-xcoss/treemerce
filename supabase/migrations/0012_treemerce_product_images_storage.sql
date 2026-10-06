-- ============================================================================
-- TREEMERCE : 0012_treemerce_product_images_storage.sql
-- 商品画像用 Storage バケット (product-images)
-- ----------------------------------------------------------------------------
--   閲覧   : 公開バケット (商品ページで画像 URL をそのまま表示するため)
--   書込み : super_admin のみ (アップロード・差し替え・削除)
--   制限   : 5MB まで / JPEG・PNG・WebP のみ / products/ 配下のみ
-- 非公開商品の画像も URL を知っていれば見えるため、ファイル名は推測できない
-- ランダム名 (UUID) で保存する (アプリ側で付与)。
--
-- storage スキーマが存在しない環境 (ローカルの PGlite テスト等) では何もしない。
-- ============================================================================

begin;

do $do$
begin
  if to_regclass('storage.buckets') is null or to_regclass('storage.objects') is null then
    raise notice '0012: storage スキーマが無いためスキップしました';
    return;
  end if;

  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('product-images', 'product-images', true, 5242880,
          array['image/jpeg', 'image/png', 'image/webp'])
  on conflict (id) do update
    set public             = excluded.public,
        file_size_limit    = excluded.file_size_limit,
        allowed_mime_types = excluded.allowed_mime_types;

  execute 'drop policy if exists treemerce_product_images_insert on storage.objects';
  execute 'drop policy if exists treemerce_product_images_update on storage.objects';
  execute 'drop policy if exists treemerce_product_images_delete on storage.objects';

  execute $p$
    create policy treemerce_product_images_insert on storage.objects
      for insert to authenticated
      with check (
        bucket_id = 'product-images'
        and name like 'products/%'
        and app.is_super_admin()
      )
  $p$;

  execute $p$
    create policy treemerce_product_images_update on storage.objects
      for update to authenticated
      using (bucket_id = 'product-images' and app.is_super_admin())
      with check (
        bucket_id = 'product-images'
        and name like 'products/%'
        and app.is_super_admin()
      )
  $p$;

  execute $p$
    create policy treemerce_product_images_delete on storage.objects
      for delete to authenticated
      using (bucket_id = 'product-images' and app.is_super_admin())
  $p$;
end;
$do$;

commit;
