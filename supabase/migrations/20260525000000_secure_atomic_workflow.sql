-- Repair deployed schemas and make submission review atomic and authorized.

alter table public.recording_analysis_jobs
  drop constraint if exists recording_analysis_jobs_kind_check;
alter table public.recording_analysis_jobs
  add constraint recording_analysis_jobs_kind_check check (
    kind in ('gpt_eval', 'mediapipe_hands', 'yolo_objects', 'sam_segments',
             'temporal_actions', 'gaussian_splat')
  );

drop policy if exists "service role full access" on public.recordings;
drop policy if exists "users update own profile" on public.profiles;

drop policy if exists "labs create own tasks" on public.tasks;
create policy "labs create own tasks" on public.tasks for insert to authenticated
with check (
  lab_id = auth.uid()
  and exists (select 1 from public.profiles p where p.id = auth.uid() and p.role in ('lab', 'admin'))
);

drop policy if exists "labs update own tasks" on public.tasks;
create policy "labs update own tasks" on public.tasks for update to authenticated
using (
  lab_id = auth.uid()
  and exists (select 1 from public.profiles p where p.id = auth.uid() and p.role in ('lab', 'admin'))
)
with check (
  lab_id = auth.uid()
  and exists (select 1 from public.profiles p where p.id = auth.uid() and p.role in ('lab', 'admin'))
);

drop policy if exists "authenticated upload recordings" on storage.objects;
create policy "authenticated upload recordings"
on storage.objects for insert to authenticated
with check (bucket_id = 'recordings' and owner_id = auth.uid()::text);

drop policy if exists "owners read recording objects" on storage.objects;
create policy "owners read recording objects"
on storage.objects for select to authenticated
using (bucket_id = 'recordings' and owner_id = auth.uid()::text);

drop policy if exists "owners update recording objects" on storage.objects;
create policy "owners update recording objects"
on storage.objects for update to authenticated
using (bucket_id = 'recordings' and owner_id = auth.uid()::text)
with check (bucket_id = 'recordings' and owner_id = auth.uid()::text);

drop policy if exists "collectors read recording bundle objects" on storage.objects;
create policy "collectors read recording bundle objects"
on storage.objects for select to authenticated
using (
  bucket_id = 'recordings'
  and exists (
    select 1 from public.recordings r
    where r.id::text = (storage.foldername(name))[1]
      and r.collector_id = auth.uid()
  )
);

drop policy if exists "labs read task recording objects" on storage.objects;
create policy "labs read task recording objects"
on storage.objects for select to authenticated
using (
  bucket_id = 'recordings'
  and exists (
    select 1
    from public.recordings r
    join public.tasks t on t.id = r.bounty_id
    where r.id::text = (storage.foldername(name))[1]
      and t.lab_id = auth.uid()
  )
);

create index if not exists recordings_collector_created_at_idx
on public.recordings(collector_id, created_at desc);

create unique index if not exists submissions_task_collector_storage_unique
on public.submissions(task_id, collector_id, storage_path);

create unique index if not exists earnings_submission_id_unique
on public.earnings(submission_id) where submission_id is not null;

create or replace function public.review_submission(
  p_submission_id uuid,
  p_decision text
)
returns table(task_id uuid, status text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_task_id uuid;
  v_collector_id uuid;
  v_bounty numeric;
  v_status text;
  v_lab_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_decision not in ('approved', 'rejected') then
    raise exception 'Invalid review decision' using errcode = '22023';
  end if;

  select s.task_id, s.collector_id, s.status, t.lab_id, t.bounty_amount
  into v_task_id, v_collector_id, v_status, v_lab_id, v_bounty
  from public.submissions s
  join public.tasks t on t.id = s.task_id
  where s.id = p_submission_id
  for update of s, t;

  if not found then
    raise exception 'Submission not found' using errcode = 'P0002';
  end if;
  if v_lab_id <> auth.uid() or not exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role in ('lab', 'admin')
  ) then
    raise exception 'Not authorized to review this submission' using errcode = '42501';
  end if;

  if v_status = p_decision then
    return query select v_task_id, v_status;
    return;
  end if;
  if v_status <> 'pending' then
    raise exception 'Submission has already been reviewed' using errcode = 'P0001';
  end if;

  update public.submissions
  set status = p_decision
  where id = p_submission_id;

  if p_decision = 'approved' then
    insert into public.earnings (collector_id, submission_id, amount, status)
    values (v_collector_id, p_submission_id, v_bounty, 'pending');

    update public.tasks
    set quantity_filled = least(quantity_needed, quantity_filled + 1),
        status = case
          when quantity_filled + 1 >= quantity_needed then 'completed'
          else status
        end
    where id = v_task_id;
  end if;

  return query select v_task_id, p_decision;
end;
$$;

revoke all on function public.review_submission(uuid, text) from public;
grant execute on function public.review_submission(uuid, text) to authenticated;
