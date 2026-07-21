-- DataHarvest consolidated schema. Keep in sync with supabase/migrations.

-- Base schema required by the timestamped analysis-pipeline migrations.

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role text not null default 'collector' check (role in ('collector', 'lab', 'admin')),
  display_name text,
  created_at timestamptz not null default now()
);
alter table public.profiles enable row level security;
create policy "users read own profile" on public.profiles for select to authenticated using (id = auth.uid());
create policy "users insert own profile" on public.profiles for insert to authenticated with check (id = auth.uid());

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.profiles (id, role, display_name)
  values (
    new.id,
    case when new.raw_user_meta_data->>'role' in ('collector', 'lab')
      then new.raw_user_meta_data->>'role' else 'collector' end,
    coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email, '@', 1))
  );
  return new;
end;
$$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();

create table if not exists public.collector_profiles (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  capabilities text[] not null default '{}',
  location_city text,
  questionnaire_data jsonb,
  created_at timestamptz not null default now()
);
alter table public.collector_profiles enable row level security;
create policy "collectors read own" on public.collector_profiles for select to authenticated using (user_id = auth.uid());
create policy "collectors insert own" on public.collector_profiles for insert to authenticated with check (user_id = auth.uid());
create policy "collectors update own" on public.collector_profiles for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

create table if not exists public.tasks (
  id uuid primary key default gen_random_uuid(),
  lab_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  description text,
  data_type text default 'video',
  objects text[] not null default '{}',
  required_capabilities text[] not null default '{}',
  bounty_amount numeric not null default 0 check (bounty_amount >= 0),
  quantity_needed integer not null default 1 check (quantity_needed > 0),
  quantity_filled integer not null default 0 check (quantity_filled >= 0),
  deadline timestamptz,
  status text not null default 'open' check (status in ('open', 'closed', 'completed')),
  created_at timestamptz not null default now()
);
alter table public.tasks enable row level security;
create policy "authenticated read tasks" on public.tasks for select to authenticated using (true);
create policy "labs create own tasks" on public.tasks for insert to authenticated
with check (
  lab_id = auth.uid()
  and exists (select 1 from public.profiles p where p.id = auth.uid() and p.role in ('lab', 'admin'))
);
create policy "labs update own tasks" on public.tasks for update to authenticated
using (
  lab_id = auth.uid()
  and exists (select 1 from public.profiles p where p.id = auth.uid() and p.role in ('lab', 'admin'))
)
with check (
  lab_id = auth.uid()
  and exists (select 1 from public.profiles p where p.id = auth.uid() and p.role in ('lab', 'admin'))
);

create table if not exists public.recordings (
  id uuid primary key default gen_random_uuid(),
  bounty_id uuid references public.tasks(id) on delete set null,
  collector_id uuid not null references public.profiles(id) on delete cascade,
  device_model text,
  duration_ms integer,
  size_bytes bigint,
  gps_lat double precision,
  gps_lon double precision,
  gps_accuracy_m double precision,
  storage_path text not null,
  streams text[] default '{}',
  status text not null default 'uploaded' check (status in ('uploaded', 'analyzing', 'analyzed', 'analysis_failed')),
  is_scoring boolean not null default true,
  success boolean,
  success_reasoning text,
  score integer check (score between 0 and 10),
  score_reasoning text,
  created_at timestamptz not null default now()
);
alter table public.recordings enable row level security;
create policy "collectors read own recordings" on public.recordings for select to authenticated using (collector_id = auth.uid());
create policy "labs read task recordings" on public.recordings for select to authenticated
using (exists (select 1 from public.tasks t where t.id = bounty_id and t.lab_id = auth.uid()));

create table if not exists public.submissions (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.tasks(id) on delete cascade,
  collector_id uuid not null references public.profiles(id) on delete cascade,
  storage_path text not null,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  metadata jsonb default '{}',
  created_at timestamptz not null default now(),
  constraint submissions_task_collector_storage_unique unique (task_id, collector_id, storage_path)
);
alter table public.submissions enable row level security;
create policy "collectors read own submissions" on public.submissions for select to authenticated using (collector_id = auth.uid());
create policy "labs read task submissions" on public.submissions for select to authenticated
using (exists (select 1 from public.tasks t where t.id = task_id and t.lab_id = auth.uid()));

create table if not exists public.earnings (
  id uuid primary key default gen_random_uuid(),
  collector_id uuid not null references public.profiles(id) on delete cascade,
  submission_id uuid references public.submissions(id) on delete set null,
  amount numeric not null default 0 check (amount >= 0),
  status text not null default 'pending' check (status in ('pending', 'paid', 'cancelled')),
  created_at timestamptz not null default now()
);
alter table public.earnings enable row level security;
create policy "collectors read own earnings" on public.earnings for select to authenticated using (collector_id = auth.uid());

create index if not exists recordings_bounty_id_idx on public.recordings(bounty_id);
create index if not exists recordings_collector_id_idx on public.recordings(collector_id);
create index if not exists submissions_task_id_idx on public.submissions(task_id);
create index if not exists submissions_collector_id_idx on public.submissions(collector_id);
create index if not exists earnings_collector_id_idx on public.earnings(collector_id);

insert into storage.buckets (id, name, public)
values ('recordings', 'recordings', false)
on conflict (id) do update set public = false;


alter table public.recordings
  add column if not exists summary text,
  add column if not exists detected_objects jsonb,
  add column if not exists analysis_artifacts jsonb;

alter table public.recordings
  alter column is_scoring set default true;

alter table public.tasks
  add column if not exists objects text[] not null default '{}';

create table if not exists public.recording_analysis_jobs (
  id uuid primary key default gen_random_uuid(),
  recording_id uuid not null references public.recordings(id) on delete cascade,
  kind text not null,
  status text not null default 'pending',
  artifact_path text,
  summary jsonb,
  error text,
  started_at timestamptz,
  finished_at timestamptz,
  created_at timestamptz not null default now(),
  unique (recording_id, kind),
  constraint recording_analysis_jobs_kind_check check (
    kind in (
      'gpt_eval',
      'mediapipe_hands',
      'yolo_objects',
      'sam_segments',
      'temporal_actions'
    )
  ),
  constraint recording_analysis_jobs_status_check check (
    status in ('pending', 'running', 'succeeded', 'failed')
  )
);

alter table public.recording_analysis_jobs enable row level security;

drop policy if exists "collectors read own recording analysis jobs"
  on public.recording_analysis_jobs;
create policy "collectors read own recording analysis jobs"
  on public.recording_analysis_jobs
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.recordings r
      where r.id = recording_analysis_jobs.recording_id
        and r.collector_id = auth.uid()
    )
  );

drop policy if exists "labs read task recording analysis jobs"
  on public.recording_analysis_jobs;
create policy "labs read task recording analysis jobs"
  on public.recording_analysis_jobs
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.recordings r
      join public.tasks t on t.id = r.bounty_id
      where r.id = recording_analysis_jobs.recording_id
        and t.lab_id = auth.uid()
    )
  );

create index if not exists recording_analysis_jobs_recording_id_idx
  on public.recording_analysis_jobs(recording_id);

create index if not exists recordings_bounty_id_idx
  on public.recordings(bounty_id);


-- Add LiDAR depth grid dimensions to recordings so depth.bin can be decoded
-- without an out-of-band metadata file. Record format is:
--   per-frame: 8 bytes (double timestamp) + depth_width * depth_height * 4 bytes (float32 metres)

alter table public.recordings
  add column if not exists depth_width integer,
  add column if not exists depth_height integer,
  add column if not exists depth_frame_count integer;

-- Sanity check: if any of width/height/frame_count is set, all three must be set together
alter table public.recordings
  drop constraint if exists recordings_depth_dims_complete;
alter table public.recordings
  add constraint recordings_depth_dims_complete
  check (
    (depth_width is null and depth_height is null and depth_frame_count is null)
    or (depth_width is not null and depth_height is not null and depth_frame_count is not null)
  );


-- Add 'gaussian_splat' to the recording_analysis_jobs kind enum so the
-- splatfacto pipeline can register/track jobs alongside the other analyzers.

alter table public.recording_analysis_jobs
  drop constraint if exists recording_analysis_jobs_kind_check;

alter table public.recording_analysis_jobs
  add constraint recording_analysis_jobs_kind_check check (
    kind in (
      'gpt_eval',
      'mediapipe_hands',
      'yolo_objects',
      'sam_segments',
      'temporal_actions',
      'gaussian_splat'
    )
  );


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
