// src/utils/simulator.ts
import { createSupabaseClient } from "./supabase"
import type { Database } from "../types/supabase"

type UsageEventRow = Database["public"]["Tables"]["usage_events"]["Row"]

export type TrafficEventProperties = {
  endpoint: string
  region: string
  tokens_used: number
  is_flagged_anomaly: boolean
  status_code: number
}

export type TrafficConfig = {
  endpoint: string
  minTokens: number
  maxTokens: number
  isAnomaly?: boolean
  anomalyThreshold: number // 이 기준을 넘으면 이상치로 간주
}

export type InjectedUsageEvent = UsageEventRow & {
  properties: TrafficEventProperties
}

function normalizeTokenConfig(config: TrafficConfig) {
  const minTokens = Math.floor(config.minTokens)
  const maxTokens = Math.floor(config.maxTokens)
  const anomalyThreshold = Math.floor(config.anomalyThreshold)

  if (!Number.isFinite(minTokens) || !Number.isFinite(maxTokens) || !Number.isFinite(anomalyThreshold)) {
    throw new Error("토큰 설정값은 숫자여야 합니다.")
  }

  if (minTokens < 0 || maxTokens < 0 || anomalyThreshold < 0) {
    throw new Error("토큰 설정값은 0 이상이어야 합니다.")
  }

  if (minTokens > maxTokens) {
    throw new Error("최소 토큰은 최대 토큰보다 클 수 없습니다.")
  }

  return { minTokens, maxTokens, anomalyThreshold }
}

function getRandomIntInclusive(min: number, max: number) {
  return Math.floor(Math.random() * (max - min + 1)) + min
}

export async function injectTrafficSpike(
  accountId: string,
  config: TrafficConfig,
  count: number = 1,
): Promise<InjectedUsageEvent[]> {
  const supabase = createSupabaseClient()
  if (!supabase) throw new Error("Supabase 클라이언트가 없습니다.")
  if (!accountId) throw new Error("계정 ID가 필요합니다.")
  if (count < 1) throw new Error("발생 건수는 1 이상이어야 합니다.")

  const { minTokens, maxTokens, anomalyThreshold } = normalizeTokenConfig(config)

  const events = Array.from({ length: count }).map(() => {
    // 💡 이상치 발생 버튼을 눌렀다면, 무조건 Threshold 이상의 거대한 토큰을 발생시킴
    const tokens = config.isAnomaly 
      ? getRandomIntInclusive(anomalyThreshold + 1, anomalyThreshold + 5000)
      : getRandomIntInclusive(minTokens, maxTokens)

    const uniqueId = `evt_${Date.now()}_${Math.random().toString(36).substring(2, 9)}`
    const isFlaggedAnomaly = tokens > anomalyThreshold
    const properties: TrafficEventProperties = {
      endpoint: config.endpoint,
      region: "ap-northeast-2",
      tokens_used: tokens,
      is_flagged_anomaly: isFlaggedAnomaly,
      status_code: isFlaggedAnomaly ? 429 : 200,
    }
    
    return {
      account_id: accountId,
      idempotency_key: uniqueId,
      event_name: "api_request",
      timestamp: new Date().toISOString(),
      // 💡 추후 정산 엔진이 이 properties 데이터를 뜯어서 요금을 계산합니다.
      properties,
    }
  })

  const { data, error } = await supabase.from("usage_events").insert(events).select()
  if (error) throw error

  return data as InjectedUsageEvent[]
}
