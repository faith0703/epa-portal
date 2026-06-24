-- ePA Portal Migration 002: audit + version control + scale indexes
-- Applied live 2026-06-24 (Supabase). This is the exact version that ran.

create index if not exists idx_audit_created on audit_log (created_at desc);
create index if not exists idx_audit_actor on audit_log (actor_code);
create index if not exists idx_audit_action on audit_log (action);
create index if not exists idx_audit_target on audit_log (target_code);
create index if not exists idx_subs_cycle on pa_submissions (cycle_id);
create index if not exists idx_subs_emp_cycle on pa_submissions (employee_code, cycle_id);
create index if not exists idx_subs_status on pa_submissions (status);

create or replace function current_emp_code() returns text language sql stable security definer set search_path = public as $fn$ select employee_code from profiles where id = auth.uid(); $fn$;

create table if not exists pa_submission_versions (id bigint generated always as identity primary key, submission_id uuid not null, employee_code text, cycle_id uuid, version int not null, status text, section_data jsonb, manager_section_comments jsonb, saved_by text, saved_at timestamptz not null default now());
create index if not exists idx_ver_submission on pa_submission_versions (submission_id, version desc);
create index if not exists idx_ver_emp on pa_submission_versions (employee_code);

create or replace function snapshot_submission() returns trigger language plpgsql security definer set search_path = public as $fn$ declare next_version int; begin if (tg_op = 'UPDATE' and new.section_data is not distinct from old.section_data and new.manager_section_comments is not distinct from old.manager_section_comments and new.status is not distinct from old.status) then return new; end if; select coalesce(max(version),0)+1 into next_version from pa_submission_versions where submission_id = new.id; insert into pa_submission_versions (submission_id, employee_code, cycle_id, version, status, section_data, manager_section_comments, saved_by) values (new.id, new.employee_code, new.cycle_id, next_version, new.status, new.section_data, new.manager_section_comments, coalesce(current_emp_code(),'system')); return new; end; $fn$;

drop trigger if exists trg_snapshot on pa_submissions;
create trigger trg_snapshot after insert or update on pa_submissions for each row execute function snapshot_submission();

revoke update, delete on audit_log from authenticated, anon;
alter table pa_submission_versions enable row level security;
drop policy if exists versions_readable on pa_submission_versions;
create policy versions_readable on pa_submission_versions for select to authenticated using (true);
revoke insert, update, delete on pa_submission_versions from authenticated, anon;

create table if not exists schema_migrations (id text primary key, applied_at timestamptz not null default now(), note text);
alter table schema_migrations enable row level security;
insert into schema_migrations (id, note) values ('002_audit_versioning', 'Indexes, version snapshots, log hardening') on conflict (id) do nothing;
