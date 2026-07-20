-- ============================================================
-- DataHarvest — Complete Database Setup (run this ONCE)
-- Paste this entire file into Supabase SQL Editor and click RUN
-- ============================================================

-- 1. PROFILES (extends Supabase auth.users)
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role text not null default 'collector' check (role in ('collector', 'lab', 'admin')),
  display_name text,
  created_at timestamptz not null default now()
);
alter table public.profiles enable row level security;
create policy "users read own profile" on public.profiles for select to authenticated using (id = auth.uid());
create policy "users update own profile" on public.profiles for update to authenticated using (id = auth.uid());
create policy "users insert own profile" on public.profiles for insert to authenticated with check (id = auth.uid());

-- Auto-create profile on signup
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
begin
  insert into public.profiles (id, role, display_name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'role', 'collector'),
    coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email, '@', 1))
  );
  return new;
end;
$$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- 2. COLLECTOR PROFILES (extra collector metadata)
create table if not exists public.collector_profiles (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  capabilities text[] not null default '{}',
  location_city text,
  questionnaire_data jsonb,
  created_at timestamptz not null default now()
);
alter table public.collector_profiles enable row level security;
create policy "collectors read own" on public.collector_profiles for select to authenticated using (user_id = auth.uid());
create policy "collectors upsert own" on public.collector_profiles for insert to authenticated with check (user_id = auth.uid());
create policy "collectors update own" on public.collector_profiles for update to authenticated using (user_id = auth.uid());

-- 3. TASKS (bounties posted by labs)
create table if not exists public.tasks (
  id uuid primary key default gen_random_uuid(),
  lab_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  description text,
  data_type text default 'video',
  objects text[] not null default '{}',
  required_capabilities text[] not null default '{}',
  bounty_amount numeric not null default 0,
  quantity_needed integer not null default 1,
  quantity_filled integer not null default 0,
  deadline timestamptz,
  status text not null default 'open' check (status in ('open', 'closed', 'completed')),
  created_at timestamptz not null default now()
);
alter table public.tasks enable row level security;
create policy "anyone can read tasks" on public.tasks for select to authenticated using (true);
create policy "labs create own tasks" on public.tasks for insert to authenticated with check (lab_id = auth.uid());
create policy "labs update own tasks" on public.tasks for update to authenticated using (lab_id = auth.uid());

-- 4. RECORDINGS (uploaded sensor bundles)
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
  summary text,
  success boolean,
  success_reasoning text,
  score integer,
  score_reasoning text,
  detected_objects jsonb,
  analysis_artifacts jsonb,
  depth_width integer,
  depth_height integer,
  depth_frame_count integer,
  created_at timestamptz not null default now()
);
alter table public.recordings enable row level security;
create policy "collectors read own recordings" on public.recordings for select to authenticated
  using (collector_id = auth.uid());
create policy "labs read task recordings" on public.recordings for select to authenticated
  using (exists (select 1 from public.tasks t where t.id = bounty_id and t.lab_id = auth.uid()));
create policy "service role full access" on public.recordings for all using (true) with check (true);

-- 5. SUBMISSIONS (links collectors to tasks)
create table if not exists public.submissions (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.tasks(id) on delete cascade,
  collector_id uuid not null references public.profiles(id) on delete cascade,
  storage_path text not null,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  metadata jsonb default '{}',
  created_at timestamptz not null default now()
);
alter table public.submissions enable row level security;
create policy "collectors read own submissions" on public.submissions for select to authenticated
  using (collector_id = auth.uid());
create policy "labs read task submissions" on public.submissions for select to authenticated
  using (exists (select 1 from public.tasks t where t.id = task_id and t.lab_id = auth.uid()));
create policy "labs update task submissions" on public.submissions for update to authenticated
  using (exists (select 1 from public.tasks t where t.id = task_id and t.lab_id = auth.uid()));

-- 6. EARNINGS (payment tracking)
create table if not exists public.earnings (
  id uuid primary key default gen_random_uuid(),
  collector_id uuid not null references public.profiles(id) on delete cascade,
  submission_id uuid references public.submissions(id) on delete set null,
  amount numeric not null default 0,
  status text not null default 'pending' check (status in ('pending', 'paid', 'cancelled')),
  created_at timestamptz not null default now()
);
alter table public.earnings enable row level security;
create policy "collectors read own earnings" on public.earnings for select to authenticated
  using (collector_id = auth.uid());

-- 7. RECORDING ANALYSIS JOBS (AI pipeline status)
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
    kind in ('gpt_eval', 'mediapipe_hands', 'yolo_objects', 'sam_segments', 'temporal_actions', 'gaussian_splat')
  ),
  constraint recording_analysis_jobs_status_check check (
    status in ('pending', 'running', 'succeeded', 'failed')
  )
);
alter table public.recording_analysis_jobs enable row level security;
create policy "collectors read own analysis jobs" on public.recording_analysis_jobs for select to authenticated
  using (exists (select 1 from public.recordings r where r.id = recording_id and r.collector_id = auth.uid()));
create policy "labs read task analysis jobs" on public.recording_analysis_jobs for select to authenticated
  using (exists (
    select 1 from public.recordings r join public.tasks t on t.id = r.bounty_id
    where r.id = recording_id and t.lab_id = auth.uid()
  ));

-- 8. INDEXES
create index if not exists recordings_bounty_id_idx on public.recordings(bounty_id);
create index if not exists recordings_collector_id_idx on public.recordings(collector_id);
create index if not exists recording_analysis_jobs_recording_id_idx on public.recording_analysis_jobs(recording_id);
create index if not exists submissions_task_id_idx on public.submissions(task_id);
create index if not exists submissions_collector_id_idx on public.submissions(collector_id);
create index if not exists earnings_collector_id_idx on public.earnings(collector_id);

-- 9. STORAGE BUCKET
insert into storage.buckets (id, name, public) values ('recordings', 'recordings', false)
on conflict (id) do nothing;

-- ✅ Done! All tables, policies, indexes, and storage bucket created.
