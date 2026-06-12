// utils/supabase.ts
import { createClient } from '@supabase/supabase-js'
import type { Database } from '../types/supabase'

export function createSupabaseClient() {
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL
  const supabaseKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY

  if (!supabaseUrl || !supabaseKey) {
    return null
  }

  return createClient<Database>(supabaseUrl, supabaseKey)
}
