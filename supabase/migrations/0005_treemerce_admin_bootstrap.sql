-- ============================================================================
-- TREEMERCE : 0005_treemerce_admin_bootstrap.sql
-- 管理者ロールの付与/剥奪 RPC
-- ----------------------------------------------------------------------------
-- 最初の1人 (super_admin) は SQL Editor から直接 INSERT して作る:
--
--   insert into public.admin_roles (auth_user_id, role)
--   select id, 'super_admin' from auth.users where email = 'you@example.com'
--   on conflict (auth_user_id) do update
--     set role = 'super_admin', revoked_at = null;
--
-- 2人目以降は super_admin が下記 RPC (管理画面) から付与できる。
-- ============================================================================

begin;

create or replace function public.treemerce_admin_grant_role(
  p_user_email text,
  p_role       public.admin_role_name default 'admin'
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_uid    uuid;
  v_before public.admin_roles%rowtype;
  v_after  public.admin_roles%rowtype;
begin
  -- SECURITY DEFINER 内では current_user が所有者になるため session_user で判定する
  if session_user <> 'postgres' and coalesce(app.admin_role(), '') <> 'super_admin' then
    raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: super_admin のみ実行できます' using errcode = '42501';
  end if;

  select id into v_uid from auth.users where lower(email) = lower(btrim(p_user_email));
  if v_uid is null then
    raise exception 'TREEMERCE_USER_NOT_FOUND: 対象ユーザーが見つかりません' using errcode = '22023';
  end if;

  select * into v_before from public.admin_roles where auth_user_id = v_uid;

  insert into public.admin_roles (auth_user_id, role, granted_by)
  values (v_uid, p_role, auth.uid())
  on conflict (auth_user_id) do update
    set role = excluded.role, granted_by = excluded.granted_by,
        granted_at = now(), revoked_at = null
  returning * into v_after;

  insert into public.admin_audit_logs
    (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
  values (auth.uid(), coalesce(app.admin_role(), 'super_admin'), 'admin_role.grant', 'admin_roles',
          v_after.id, to_jsonb(v_before), to_jsonb(v_after), '管理者ロール付与');

  return jsonb_build_object('auth_user_id', v_uid, 'role', v_after.role);
end;
$fn$;

create or replace function public.treemerce_admin_revoke_role(p_user_email text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, app, pg_temp
as $fn$
declare
  v_uid    uuid;
  v_before public.admin_roles%rowtype;
  v_after  public.admin_roles%rowtype;
begin
  if session_user <> 'postgres' and coalesce(app.admin_role(), '') <> 'super_admin' then
    raise exception 'TREEMERCE_SUPER_ADMIN_ONLY: super_admin のみ実行できます' using errcode = '42501';
  end if;

  select id into v_uid from auth.users where lower(email) = lower(btrim(p_user_email));
  if v_uid is null then
    raise exception 'TREEMERCE_USER_NOT_FOUND: 対象ユーザーが見つかりません' using errcode = '22023';
  end if;
  if v_uid = auth.uid() then
    raise exception 'TREEMERCE_CANNOT_REVOKE_SELF: 自分自身の権限は剥奪できません' using errcode = '22023';
  end if;

  select * into v_before from public.admin_roles where auth_user_id = v_uid;
  update public.admin_roles set revoked_at = now()
  where auth_user_id = v_uid and revoked_at is null
  returning * into v_after;

  insert into public.admin_audit_logs
    (actor_user_id, actor_role, action, target_table, target_id, before_state, after_state, reason)
  values (auth.uid(), coalesce(app.admin_role(), 'super_admin'), 'admin_role.revoke', 'admin_roles',
          v_before.id, to_jsonb(v_before), to_jsonb(v_after), '管理者ロール剥奪');

  return jsonb_build_object('auth_user_id', v_uid, 'revoked', v_after.id is not null);
end;
$fn$;

revoke all on function public.treemerce_admin_grant_role(text, public.admin_role_name)
  from public, anon, authenticated;
revoke all on function public.treemerce_admin_revoke_role(text) from public, anon, authenticated;

grant execute on function public.treemerce_admin_grant_role(text, public.admin_role_name)
  to authenticated;
grant execute on function public.treemerce_admin_revoke_role(text) to authenticated;

commit;
