'use server'

import { createClient } from '@/lib/supabase/server'
import { revalidatePath } from 'next/cache'

type ReviewDecision = 'approved' | 'rejected'

async function reviewSubmission(submissionId: string, decision: ReviewDecision) {
  const supabase = await createClient()
  const { error } = await supabase.rpc('review_submission', {
    p_submission_id: submissionId,
    p_decision: decision,
  })

  if (error) {
    return { error: error.message }
  }

  revalidatePath('/lab/tasks', 'layout')
  return { success: true }
}

export async function approveSubmission(submissionId: string) {
  return reviewSubmission(submissionId, 'approved')
}

export async function rejectSubmission(submissionId: string) {
  return reviewSubmission(submissionId, 'rejected')
}
