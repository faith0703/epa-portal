-- ============================================================
-- ePA Portal v2.3 - RLS hardening
-- Date: 2026-07-14
-- Fixes three policies that were effectively "allow everyone":
--   1. pa_submission_versions SELECT  USING (true)  -> any employee could read
--      every other employee's appraisal history snapshots.
--   2. audit_log INSERT  WITH CHECK (true)  -> any employee could write an audit
--      row claiming to be someone else (actor spoofing).
--   3. audit_log SELECT  USING (true)  -> policy was NAMED "HR can view audit log"
--      but the predicate let any authenticated user read the whole log.
--
-- Helper functions used (both confirmed live, SECURITY DEFINER + STABLE):
--   current_emp_code() -> the caller's employee_code
--   get_my_role()      -> the caller's role ('employee' | 'manager' | 'hr')
--
-- Safe to re-run (drop if exists / create).
-- ============================================================

-- ---------- 1. pa_submission_versions: scope reads to owner / manager / HR ----------
-- Table has no manager_code column, so the manager check joins back to
-- pa_submissions via submission_id.

drop policy if exists versions_readable on pa_submission_versions;

create policy versions_read_scoped on pa_submission_versions
  for select to authenticated
  using (
    -- the employee themselves
    employee_code = current_emp_code()
    -- their manager (resolved through the parent submission)
    or exists (
      select 1 from pa_submissions s
      where s.id = pa_submission_versions.submission_id
        and s.manager_code = current_emp_code()
    )
    -- HR
    or get_my_role() = 'hr'
  );

-- ---------- 2. audit_log INSERT: actor must be the authenticated caller ----------
-- App-side logAudit() always sets actor_code = state.currentUser.employee_code,
-- so no legitimate write is affected by this tightening.

drop policy if exists "Authenticated users can insert" on audit_log;

create policy audit_insert_self on audit_log
  for insert to authenticated
  with check (actor_code = current_emp_code());

-- ---------- 3. audit_log SELECT: actually restrict to HR ----------

drop policy if exists "HR can view audit log" on audit_log;

create policy audit_select_hr on audit_log
  for select to authenticated
  using (get_my_role() = 'hr');

-- ---------- verification ----------
-- Expect exactly: audit_insert_self (INSERT), audit_select_hr (SELECT),
--                 versions_read_scoped (SELECT) -- none with a bare `true`.
select tablename, policyname, cmd,
       coalesce(qual::text,'-')       as using_expr,
       coalesce(with_check::text,'-') as check_expr
from pg_policies
where tablename in ('pa_submission_versions','audit_log')
order by tablename, cmd;
