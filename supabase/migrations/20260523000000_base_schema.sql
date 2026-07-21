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
