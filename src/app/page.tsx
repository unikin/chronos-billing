import { SimulatorDashboard } from "./simulator-dashboard"
import { createSupabaseClient } from "../../utils/supabase"

export const dynamic = "force-dynamic"

export default async function Page() {
  const supabase = createSupabaseClient()

  if (!supabase) {
    return <SimulatorDashboard initialAccounts={[]} />
  }

  const { data, error } = await supabase.from("accounts").select("*")

  if (error) {
    console.error("계정 불러오기 실패:", error)
  }

  return <SimulatorDashboard initialAccounts={data || []} />
}
