-- ============================================================
-- DataHarvest — LIVE FIX MIGRATION
-- Run this in Supabase SQL Editor to fix all 3 bugs at once.
-- Safe to run multiple times (idempotent).
-- ============================================================

-- ---------------------------------------------------------------
-- FIX 1: Update the trigger to read 'role' from user metadata
--         instead of hardcoding 'collector' for everyone.
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
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

-- ---------------------------------------------------------------
-- FIX 2: Add missing columns to collector_profiles that the
--         onboarding form writes to.
-- ---------------------------------------------------------------
ALTER TABLE public.collector_profiles
  ADD COLUMN IF NOT EXISTS location_city text,
  ADD COLUMN IF NOT EXISTS questionnaire_data jsonb;

-- ---------------------------------------------------------------
-- FIX 3: Fix all existing users whose role was hardcoded as
--         'collector' but should be 'lab' based on their signup
--         metadata. This is a one-time data repair.
-- ---------------------------------------------------------------
UPDATE public.profiles p
SET role = u.raw_user_meta_data->>'role'
FROM auth.users u
WHERE p.id = u.id
  AND u.raw_user_meta_data->>'role' = 'lab'
  AND p.role = 'collector';

-- ✅ Done! All 3 bugs are now fixed.
-- Existing lab users will now be redirected to /lab/dashboard on next login.
-- Collector onboarding will now succeed with no missing-column errors.
-- New signups will get the correct role from the form automatically.
