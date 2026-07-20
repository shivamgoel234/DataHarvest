-- ============================================================
-- DATAHARVEST MASTER DATABASE FIX
-- Run this ENTIRE script in Supabase SQL Editor:
-- https://supabase.com/dashboard/project/aewnfzrgitsuhnfrebuv/sql/new
-- ============================================================

-- FIX 1: Repair trigger to read role from user metadata (idempotent)
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
  INSERT INTO public.profiles (id, role, display_name)
  VALUES (
    new.id,
    COALESCE(new.raw_user_meta_data->>'role', 'collector'),
    COALESCE(new.raw_user_meta_data->>'display_name', split_part(new.email, '@', 1))
  );
  RETURN new;
END;
$$;

-- FIX 2: Add missing columns to collector_profiles (idempotent)
ALTER TABLE public.collector_profiles
  ADD COLUMN IF NOT EXISTS location_city text,
  ADD COLUMN IF NOT EXISTS questionnaire_data jsonb;

-- FIX 3: Repair existing users who have wrong role in DB
UPDATE public.profiles p
SET role = u.raw_user_meta_data->>'role'
FROM auth.users u
WHERE p.id = u.id
  AND u.raw_user_meta_data->>'role' IN ('lab', 'collector')
  AND p.role != u.raw_user_meta_data->>'role';

-- FIX 4 (CRITICAL): Create the missing RPC function
-- approveSubmission() calls supabase.rpc('increment_quantity_filled')
-- This function was NEVER defined. Every approval crashes without it.
CREATE OR REPLACE FUNCTION public.increment_quantity_filled(task_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
  UPDATE public.tasks
  SET quantity_filled = quantity_filled + 1
  WHERE id = task_id;
END;
$$;

-- FIX 5 (CRITICAL): Add missing INSERT RLS policy on submissions
-- Collectors can SELECT but NOT INSERT their submissions from the web app.
-- This means the web submission flow is completely broken.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'submissions'
      AND schemaname = 'public'
      AND policyname = 'collectors insert own submissions'
  ) THEN
    EXECUTE 'CREATE POLICY "collectors insert own submissions"
      ON public.submissions
      FOR INSERT TO authenticated
      WITH CHECK (collector_id = auth.uid())';
  END IF;
END $$;

-- FIX 6 (CRITICAL): Fix earnings status enum
-- Code inserts status = 'approved' but DB only allows ('pending','paid','cancelled')
-- This causes every earnings record to fail silently on approval.
ALTER TABLE public.earnings DROP CONSTRAINT IF EXISTS earnings_status_check;
ALTER TABLE public.earnings
  ADD CONSTRAINT earnings_status_check
  CHECK (status IN ('pending', 'approved', 'paid', 'cancelled'));

-- FIX 7 (CRITICAL): Add INSERT policy for earnings table
-- approveSubmission inserts into earnings but no INSERT policy exists!
-- Every approval silently fails to record earnings.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'earnings'
      AND schemaname = 'public'
      AND policyname = 'labs insert earnings on approval'
  ) THEN
    EXECUTE 'CREATE POLICY "labs insert earnings on approval"
      ON public.earnings
      FOR INSERT TO authenticated
      WITH CHECK (true)';
  END IF;
END $$;

-- FIX 8: Seed one real test task for immediate collector testing
-- Uses the first lab user's UUID automatically.
INSERT INTO public.tasks (
  lab_id,
  title,
  description,
  data_type,
  required_capabilities,
  bounty_amount,
  quantity_needed,
  status
)
SELECT
  p.id,
  'Record 30-second outdoor walking clip',
  'Walk for 30 seconds in an outdoor environment. Keep the camera steady at chest height with a firm grip. Ensure good natural lighting — avoid backlighting. Capture continuously without stopping or cutting.',
  'video',
  ARRAY['outdoor', 'video'],
  5.00,
  20,
  'open'
FROM public.profiles p
WHERE p.role = 'lab'
LIMIT 1;

-- VERIFY: Check final state of all tables
SELECT 'profiles' AS table_name, count(*) AS row_count FROM public.profiles
UNION ALL SELECT 'tasks', count(*) FROM public.tasks
UNION ALL SELECT 'collector_profiles', count(*) FROM public.collector_profiles
UNION ALL SELECT 'submissions', count(*) FROM public.submissions
UNION ALL SELECT 'earnings', count(*) FROM public.earnings;

-- VERIFY: Check all RLS policies on submissions and earnings
SELECT tablename, policyname, cmd, qual
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('submissions', 'earnings', 'tasks')
ORDER BY tablename, policyname;

-- VERIFY: Check the RPC function was created
SELECT routine_name, routine_type
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name = 'increment_quantity_filled';
