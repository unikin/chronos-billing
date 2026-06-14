"use client"

import { useState, useEffect, useRef, useCallback, useMemo } from "react"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { ResponsiveContainer, LineChart, CartesianGrid, XAxis, YAxis, Tooltip, Line, ReferenceLine, BarChart, Bar } from "recharts"
import type { Database } from "../../types/supabase"
import { injectTrafficSpike, type TrafficConfig, type TrafficEventProperties } from "../../utils/simulator"
import { createSupabaseClient } from "../../utils/supabase"

type Account = Database["public"]["Tables"]["accounts"]["Row"]
type BillableMetric = Database["public"]["Tables"]["billable_metrics"]["Row"]
type CreditLedger = Database["public"]["Tables"]["credit_ledgers"]["Row"]
type Invoice = Database["public"]["Tables"]["invoices"]["Row"]
type InvoiceLineItem = Database["public"]["Tables"]["invoice_line_items"]["Row"]
type Subscription = Database["public"]["Tables"]["subscriptions"]["Row"]

type SimConfig = Omit<TrafficConfig, "isAnomaly">

type ChartPoint = {
  time: string
  tokens: number
  cost: number
  endpoint: string
}

type SimulatorDashboardProps = {
  initialAccounts: Account[]
}

type TimeFrame = "hour" | "day" | "week" | "month"

type HistoricalPoint = {
  label: string
  tokens: number
}

type UsageEventSnapshot = {
  timestamp: string
  properties: Pick<TrafficEventProperties, "endpoint" | "tokens_used" | "is_flagged_anomaly">
}

const TOKEN_UNIT_PRICE = 0.2
const DEFAULT_RATE_CARD_ID = "22222222-2222-4222-8222-222222222222"

type InvoiceGenerationResult = {
  invoice_id?: string
  total_amount?: number
  billing_period_start?: string
  billing_period_end?: string
  status?: string
}

function getCurrentMonthInputValue() {
  const now = new Date()
  return `${now.getFullYear()}-${(now.getMonth() + 1).toString().padStart(2, "0")}`
}

function getMonthRange(monthValue: string) {
  const [year, month] = monthValue.split("-").map(Number)
  const start = new Date(Date.UTC(year, month - 1, 1))
  const end = new Date(Date.UTC(year, month, 1))
  return {
    startIso: start.toISOString(),
    endIso: end.toISOString(),
    targetDate: `${monthValue}-01`,
  }
}

function getAccountDefaultSubscriptionPeriod() {
  return getMonthRange(getCurrentMonthInputValue())
}

function formatCurrency(amount: number | null | undefined) {
  return `₩ ${Math.round(Number(amount ?? 0)).toLocaleString()}`
}

function formatDateTime(value: string | null | undefined) {
  if (!value) return "-"
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return "-"
  return date.toLocaleString("ko-KR", { dateStyle: "medium", timeStyle: "short" })
}

function formatPeriod(start: string | null, end: string | null) {
  if (!start && !end) return "기간 정보 없음"
  return `${formatDateTime(start)} ~ ${formatDateTime(end)}`
}

function getUsageBucketLabel(timestamp: string, timeFrame: TimeFrame) {
  const date = new Date(timestamp)
  if (Number.isNaN(date.getTime())) return "기타"

  if (timeFrame === "hour") {
    return `${date.getHours().toString().padStart(2, "0")}시`
  }

  if (timeFrame === "day") {
    return `${date.getMonth() + 1}/${date.getDate()}`
  }

  if (timeFrame === "week") {
    const weekOfMonth = Math.ceil(date.getDate() / 7)
    return `${date.getMonth() + 1}월 ${weekOfMonth}주`
  }

  return `${date.getMonth() + 1}월`
}

function aggregateUsageByTimeFrame(events: UsageEventSnapshot[], timeFrame: TimeFrame): HistoricalPoint[] {
  const buckets = new Map<string, number>()

  events.forEach((event) => {
    const label = getUsageBucketLabel(event.timestamp, timeFrame)
    buckets.set(label, (buckets.get(label) ?? 0) + event.properties.tokens_used)
  })

  return Array.from(buckets, ([label, tokens]) => ({ label, tokens }))
}

export function SimulatorDashboard({ initialAccounts }: SimulatorDashboardProps) {
  // 전역 상태 관리
  const [accounts, setAccounts] = useState<Account[]>(initialAccounts)
  const [activeAccount, setActiveAccount] = useState<Account | null>(null)
  const [activeTab, setActiveTab] = useState("account")

  // 폼 입력 상태
  const [newAccountName, setNewAccountName] = useState("")
  const [newTimezone, setNewTimezone] = useState("Asia/Seoul")

  //  2번 탭: 시뮬레이터 설정 및 차트 상태
  const [simConfig, setSimConfig] = useState<SimConfig>({
    endpoint: "gpt-4-turbo",
    minTokens: 10,
    maxTokens: 150,
    anomalyThreshold: 1000, // 이상치 판별 기준 (토큰 수)
  })
  const [chartData, setChartData] = useState<ChartPoint[]>([])
  const [monthlyCost, setMonthlyCost] = useState(0)
  const [anomalyAlert, setAnomalyAlert] = useState<string | null>(null)
  const [timeFrame, setTimeFrame] = useState<TimeFrame>("day")
  const [monthlyUsageEvents, setMonthlyUsageEvents] = useState<UsageEventSnapshot[]>([])
  const [isSimulating, setIsSimulating] = useState(false)
  const [isAnomalySimulating, setIsAnomalySimulating] = useState(false)
  const [invoiceMonth, setInvoiceMonth] = useState(getCurrentMonthInputValue())
  const [invoices, setInvoices] = useState<Invoice[]>([])
  const [invoiceLineItems, setInvoiceLineItems] = useState<InvoiceLineItem[]>([])
  const [metrics, setMetrics] = useState<BillableMetric[]>([])
  const [creditLedgers, setCreditLedgers] = useState<CreditLedger[]>([])
  const [activeSubscription, setActiveSubscription] = useState<Subscription | null>(null)
  const [isBillingLoading, setIsBillingLoading] = useState(false)
  const [isGeneratingInvoice, setIsGeneratingInvoice] = useState(false)
  const [billingMessage, setBillingMessage] = useState<string | null>(null)
  const [creditTopUpAmount, setCreditTopUpAmount] = useState(50000)
  const intervalRef = useRef<NodeJS.Timeout | null>(null)
  const anomalyAlertTimeoutRef = useRef<NodeJS.Timeout | null>(null)
  const dashboardLoadRequestRef = useRef(0)
  const billingLoadRequestRef = useRef(0)

  const filteredChartData = useMemo(
    () => chartData.filter((point) => point.endpoint === simConfig.endpoint),
    [chartData, simConfig.endpoint],
  )

  const historicalData = useMemo(
    () => aggregateUsageByTimeFrame(monthlyUsageEvents, timeFrame),
    [monthlyUsageEvents, timeFrame],
  )

  const metricNameById = useMemo(
    () => new Map(metrics.map((metric) => [metric.id, metric.name])),
    [metrics],
  )

  const lineItemsByInvoiceId = useMemo(() => {
    const grouped = new Map<string, InvoiceLineItem[]>()
    invoiceLineItems.forEach((item) => {
      grouped.set(item.invoice_id, [...(grouped.get(item.invoice_id) ?? []), item])
    })
    return grouped
  }, [invoiceLineItems])

  const currentBalance = creditLedgers[0]?.running_balance ?? 0

  const resetSessionMetrics = () => {
    setChartData([])
    setAnomalyAlert(null)
    if (anomalyAlertTimeoutRef.current) clearTimeout(anomalyAlertTimeoutRef.current)
  }

  const resetBillingState = () => {
    setInvoices([])
    setInvoiceLineItems([])
    setMetrics([])
    setCreditLedgers([])
    setActiveSubscription(null)
    setBillingMessage(null)
  }

  const stopSimulation = () => {
    setIsSimulating(false)
    setIsAnomalySimulating(false)
  }

  const loadDashboardData = useCallback(async (accountId: string) => {
    const requestId = dashboardLoadRequestRef.current + 1
    dashboardLoadRequestRef.current = requestId
    const supabase = createSupabaseClient()

    if (!supabase) {
      if (dashboardLoadRequestRef.current !== requestId) return
      setMonthlyCost(0)
      setMonthlyUsageEvents([])
      return
    }

    const startOfMonth = new Date(new Date().getFullYear(), new Date().getMonth(), 1).toISOString()

    const { data, error } = await supabase
      .from("v_dashboard_events")
      .select("timestamp, endpoint, tokens_used, is_flagged_anomaly")
      .eq("account_id", accountId)
      .gte("timestamp", startOfMonth)
      .order("timestamp", { ascending: true })

    if (error) {
      if (dashboardLoadRequestRef.current !== requestId) return
      console.error("대시보드 데이터 로드 실패:", error)
      setMonthlyCost(0)
      setMonthlyUsageEvents([])
      return
    }

    const usageEvents = (data ?? []).flatMap((row) => {
      if (!row.timestamp) return []

      return [{
        timestamp: row.timestamp,
        properties: {
          endpoint: row.endpoint ?? "unknown",
          tokens_used: Number(row.tokens_used ?? 0),
          is_flagged_anomaly: row.is_flagged_anomaly === true,
        },
      }]
    })

    const totalTokens = usageEvents.reduce((sum, event) => sum + event.properties.tokens_used, 0)
    if (dashboardLoadRequestRef.current !== requestId) return
    setMonthlyUsageEvents(usageEvents)
    setMonthlyCost(totalTokens * TOKEN_UNIT_PRICE)
  }, [])

  const loadBillingData = useCallback(async (accountId: string, monthValue: string) => {
    const requestId = billingLoadRequestRef.current + 1
    billingLoadRequestRef.current = requestId
    setIsBillingLoading(true)

    const supabase = createSupabaseClient()
    if (!supabase) {
      if (billingLoadRequestRef.current === requestId) {
        resetBillingState()
        setBillingMessage("Supabase 환경변수가 설정되지 않았습니다.")
        setIsBillingLoading(false)
      }
      return
    }

    const { startIso, endIso } = getMonthRange(monthValue)

    const [
      invoicesResult,
      ledgersResult,
      subscriptionsResult,
      metricsResult,
    ] = await Promise.all([
      supabase
        .from("invoices")
        .select("*")
        .eq("account_id", accountId)
        .order("billing_period_start", { ascending: false, nullsFirst: false }),
      supabase
        .from("credit_ledgers")
        .select("*")
        .eq("account_id", accountId)
        .order("created_at", { ascending: false })
        .order("id", { ascending: false }),
      supabase
        .from("subscriptions")
        .select("*")
        .eq("account_id", accountId)
        .eq("status", "Active")
        .lt("current_period_start", endIso)
        .gt("current_period_end", startIso)
        .order("current_period_start", { ascending: false })
        .limit(1),
      supabase
        .from("billable_metrics")
        .select("*"),
    ])

    if (billingLoadRequestRef.current !== requestId) return

    const firstError = invoicesResult.error ?? ledgersResult.error ?? subscriptionsResult.error ?? metricsResult.error
    if (firstError) {
      console.error("정산 데이터 로드 실패:", firstError)
      resetBillingState()
      setBillingMessage("정산 데이터를 불러오는 중 오류가 발생했습니다.")
      setIsBillingLoading(false)
      return
    }

    const loadedInvoices = invoicesResult.data ?? []
    const invoiceIds = loadedInvoices.map((invoice) => invoice.id)
    let loadedLineItems: InvoiceLineItem[] = []

    if (invoiceIds.length > 0) {
      const { data, error } = await supabase
        .from("invoice_line_items")
        .select("*")
        .in("invoice_id", invoiceIds)

      if (billingLoadRequestRef.current !== requestId) return

      if (error) {
        console.error("청구 라인아이템 로드 실패:", error)
        setBillingMessage("청구 라인아이템을 불러오는 중 오류가 발생했습니다.")
      } else {
        loadedLineItems = data ?? []
      }
    }

    setInvoices(loadedInvoices)
    setInvoiceLineItems(loadedLineItems)
    setCreditLedgers(ledgersResult.data ?? [])
    setActiveSubscription(subscriptionsResult.data?.[0] ?? null)
    setMetrics(metricsResult.data ?? [])
    setIsBillingLoading(false)
  }, [])

  const handleSelectAccount = useCallback((account: Account) => {
    stopSimulation()
    setActiveAccount(account)
    resetSessionMetrics()
    resetBillingState()
    void loadDashboardData(account.id)
    void loadBillingData(account.id, invoiceMonth)
  }, [invoiceMonth, loadBillingData, loadDashboardData])

  // 새로운 계정 DB에 인서트하기
  const handleCreateAccount = async () => {
    const trimmedAccountName = newAccountName.trim()

    if (!trimmedAccountName) return alert("조직명을 입력해주세요!")

    const supabase = createSupabaseClient()

    if (!supabase) {
      alert("Supabase 환경변수가 설정되지 않았습니다.")
      return
    }

    const { data, error } = await supabase
      .from("accounts")
      .insert([
        {
          name: trimmedAccountName,
          timezone: newTimezone,
          status: "Active",
          // parent_account_id는 1차 테스트를 위해 일단 생략합니다.
        },
      ])
      .select()
      .single()

    if (error) {
      console.error("계정 생성 실패:", error)
      alert("생성 중 에러가 발생했습니다.")
      return
    }

    const { startIso, endIso } = getAccountDefaultSubscriptionPeriod()
    const { error: subscriptionError } = await supabase
      .from("subscriptions")
      .insert({
        account_id: data.id,
        rate_card_id: DEFAULT_RATE_CARD_ID,
        billing_interval: "Monthly",
        current_period_start: startIso,
        current_period_end: endIso,
        status: "Active",
      })

    if (subscriptionError) {
      console.error("기본 구독 생성 실패:", subscriptionError)
      alert("계정은 생성됐지만 기본 구독 생성 중 에러가 발생했습니다. 3번 탭에서 관리자 권한으로 구독을 연결해주세요.")
    }

    setAccounts((currentAccounts) => [data, ...currentAccounts])
    setActiveAccount(data)
    resetSessionMetrics()
    resetBillingState()
    void loadDashboardData(data.id)
    void loadBillingData(data.id, invoiceMonth)
    setNewAccountName("")
  }

  const handleEnsureSubscription = async () => {
    if (!activeAccount) return alert("먼저 계정을 선택/활성화 해주세요!")
    if (activeSubscription) return

    const supabase = createSupabaseClient()
    if (!supabase) {
      alert("Supabase 환경변수가 설정되지 않았습니다.")
      return
    }

    const { startIso, endIso } = getMonthRange(invoiceMonth)
    const { error } = await supabase
      .from("subscriptions")
      .insert({
        account_id: activeAccount.id,
        rate_card_id: DEFAULT_RATE_CARD_ID,
        billing_interval: "Monthly",
        current_period_start: startIso,
        current_period_end: endIso,
        status: "Active",
      })

    if (error) {
      console.error("구독 생성 실패:", error)
      alert(error.message)
      return
    }

    setBillingMessage(`${invoiceMonth} 구독이 관리자 권한으로 연결되었습니다.`)
    await loadBillingData(activeAccount.id, invoiceMonth)
  }

  const handleCancelActiveSubscription = async () => {
    if (!activeAccount || !activeSubscription) return
    if (!window.confirm("현재 선택 월과 겹치는 활성 구독을 취소할까요?")) return

    const supabase = createSupabaseClient()
    if (!supabase) return

    const { error } = await supabase
      .from("subscriptions")
      .update({ status: "Canceled" })
      .eq("id", activeSubscription.id)

    if (error) {
      console.error("구독 취소 실패:", error)
      alert(error.message)
      return
    }

    setBillingMessage("활성 구독이 취소되었습니다.")
    await loadBillingData(activeAccount.id, invoiceMonth)
  }

  const handleGenerateInvoice = async () => {
    if (!activeAccount) return alert("먼저 계정을 선택/활성화 해주세요!")

    const supabase = createSupabaseClient()
    if (!supabase) {
      alert("Supabase 환경변수가 설정되지 않았습니다.")
      return
    }

    setIsGeneratingInvoice(true)
    setBillingMessage(null)

    const { targetDate } = getMonthRange(invoiceMonth)
    const { data, error } = await supabase.rpc("generate_monthly_invoice", {
      p_account_id: activeAccount.id,
      p_target_month: targetDate,
    })

    setIsGeneratingInvoice(false)

    if (error) {
      console.error("청구서 생성 실패:", error)
      setBillingMessage(error.message)
      return
    }

    const result = data as InvoiceGenerationResult | null
    setBillingMessage(`청구서가 생성되었습니다. ${formatCurrency(result?.total_amount)} / ${result?.invoice_id ?? "신규 청구서"}`)
    await loadBillingData(activeAccount.id, invoiceMonth)
  }

  const handleUpdateInvoiceStatus = async (invoiceId: string, status: Invoice["status"]) => {
    if (!activeAccount) return

    const supabase = createSupabaseClient()
    if (!supabase) return

    const { error } = await supabase
      .from("invoices")
      .update({ status })
      .eq("id", invoiceId)

    if (error) {
      console.error("청구서 상태 변경 실패:", error)
      alert(error.message)
      return
    }

    setBillingMessage(`관리자 권한으로 청구서 상태가 ${status}(으)로 변경되었습니다.`)
    await loadBillingData(activeAccount.id, invoiceMonth)
  }

  const handleCreditTopUp = async () => {
    if (!activeAccount) return alert("먼저 계정을 선택/활성화 해주세요!")
    const amount = Math.round(Number(creditTopUpAmount))

    if (!Number.isFinite(amount) || amount <= 0) {
      alert("충전 금액은 0보다 큰 숫자여야 합니다.")
      return
    }

    const supabase = createSupabaseClient()
    if (!supabase) return

    const { error } = await supabase
      .from("credit_ledgers")
      .insert({
        account_id: activeAccount.id,
        transaction_type: "Credit Top-up",
        amount,
        running_balance: currentBalance + amount,
        reference_type: "manual",
        reference_id: `simulator:${Date.now()}`,
      })

    if (error) {
      console.error("크레딧 충전 실패:", error)
      alert(error.message)
      return
    }

    setBillingMessage(`${formatCurrency(amount)} 크레딧이 충전되었습니다.`)
    await loadBillingData(activeAccount.id, invoiceMonth)
  }

  const handleInvoiceMonthChange = (monthValue: string) => {
    setInvoiceMonth(monthValue)
    if (activeAccount) void loadBillingData(activeAccount.id, monthValue)
  }

  // 계정 상태를 'Archived'로 변경하는 함수
  const handleDeleteAccount = async (accountId: string) => {
    if (!window.confirm("정말로 이 계정을 삭제하시겠습니까? (상태가 Archived로 변경됩니다)")) return

    const supabase = createSupabaseClient()
    if (!supabase) return

    const { error } = await supabase
      .from("accounts")
      .update({ status: "Archived" })
      .eq("id", accountId)

    if (error) {
      console.error("계정 삭제 실패:", error)
      return alert("계정 삭제 중 오류가 발생했습니다.")
    }

    setAccounts((current) => current.filter((acc) => acc.id !== accountId))
    if (activeAccount?.id === accountId) {
      stopSimulation()
      setActiveAccount(null)
      resetSessionMetrics()
      resetBillingState()
      dashboardLoadRequestRef.current += 1
      billingLoadRequestRef.current += 1
      setMonthlyCost(0)
      setMonthlyUsageEvents([])
    }
  }

  const triggerTraffic = useCallback(async (isAnomaly: boolean = false) => {
    if (!activeAccount) return alert("먼저 계정을 선택/활성화 해주세요!")

    try {
      const result = await injectTrafficSpike(activeAccount.id, { ...simConfig, isAnomaly })

      // 화면 차트 및 요금 업데이트 로직
      if (result && result.length > 0) {
        const event = result[0]
        const properties = event.properties
        const generatedTokens = properties.tokens_used
        // 임시 과금 로직: 1토큰당 0.2원 (추후 3번 탭 정산 엔진에서 정교화)
        const cost = generatedTokens * TOKEN_UNIT_PRICE

        if (properties.is_flagged_anomaly) {
          if (anomalyAlertTimeoutRef.current) clearTimeout(anomalyAlertTimeoutRef.current)
          setAnomalyAlert(`[경고] 비정상적인 트래픽 감지! (${generatedTokens.toLocaleString()} 토큰 초과)`)
          anomalyAlertTimeoutRef.current = setTimeout(() => setAnomalyAlert(null), 4000)
        }

        setMonthlyCost((prev) => prev + cost)
        setMonthlyUsageEvents((prev) => [...prev, { timestamp: event.timestamp, properties }])
        setChartData((prev) => {
          const newData = [...prev, { time: new Date().toLocaleTimeString(), tokens: generatedTokens, cost, endpoint: properties.endpoint }]
          return newData.slice(-15) // 최근 15개 데이터만 유지하여 차트 애니메이션 구현
        })
      }
    } catch (error) {
      console.error("트래픽 발생 에러", error)
      stopSimulation()
      alert(error instanceof Error ? error.message : "트래픽 발생 중 오류가 발생했습니다.")
    }
  }, [activeAccount, simConfig])

  // 🔴 지속 발생 (일반 & 이상치) 토글 로직
  useEffect(() => {
    if (isSimulating || isAnomalySimulating) {
      intervalRef.current = setInterval(() => {
        triggerTraffic(isAnomalySimulating)
      }, 1000) // 1초마다 쏘기
    } else {
      if (intervalRef.current) clearInterval(intervalRef.current)
    }
    return () => {
      if (intervalRef.current) clearInterval(intervalRef.current)
    }
  }, [isSimulating, isAnomalySimulating, triggerTraffic])

  useEffect(() => {
    return () => {
      if (anomalyAlertTimeoutRef.current) clearTimeout(anomalyAlertTimeoutRef.current)
    }
  }, [])

  // 삭제된(Archived) 계정을 걸러내는 필터링 변수 (return 문 바로 위에 작성)
  const visibleAccounts = accounts.filter(acc => acc.status !== "Archived")

  return (
    <div className="container mx-auto max-w-5xl p-10 min-h-screen">
      {/* 상단 헤더 & 활성 계정 표시 배지 */}
      <div className="flex justify-between items-end mb-8">
        <div>
          <h1 className="text-4xl font-extrabold tracking-tight">Chronos-Billing</h1>
          <p className="text-muted-foreground mt-2">Bitemporal 과금 시스템 시뮬레이터</p>
        </div>
        <div className={`px-4 py-2 rounded-full font-semibold text-sm ${activeAccount ? "bg-green-100 text-green-800" : "bg-primary/10 text-primary"}`}>
          {activeAccount ? `🟢 활성 계정: ${activeAccount.name} (${activeAccount.timezone})` : "🟡 활성 계정: 아직 선택되지 않음"}
        </div>
      </div>

      <Tabs value={activeTab} onValueChange={setActiveTab} className="w-full">
        <TabsList className="grid w-full grid-cols-3 h-12 mb-8">
          <TabsTrigger value="account" className="text-base">1. 계정 관리</TabsTrigger>
          <TabsTrigger value="dashboard" className="text-base">2. 고객 대시보드</TabsTrigger>
          <TabsTrigger value="invoice" className="text-base">3. 청구서 및 정산</TabsTrigger>
        </TabsList>

        {/* 탭 1: 계정 관리 화면 */}
        <TabsContent value="account">
          <div className="grid grid-cols-2 gap-6">
            {/* 좌측: 계정 생성 폼 */}
            <Card>
              <CardHeader>
                <CardTitle>신규 고객(계정) 등록</CardTitle>
                <CardDescription>조직을 만들면 이번 달 기본 구독이 자동으로 연결됩니다.</CardDescription>
              </CardHeader>
              <CardContent className="space-y-4">
                <div className="space-y-2">
                  <Label htmlFor="org-name">조직명</Label>
                  <Input
                    id="org-name"
                    placeholder="예: Test Corp"
                    value={newAccountName}
                    onChange={(e) => setNewAccountName(e.target.value)}
                  />
                </div>
                <div className="space-y-2">
                  <Label>기준 타임존 (정산 기준일)</Label>
                  <Select value={newTimezone} onValueChange={setNewTimezone}>
                    <SelectTrigger>
                      <SelectValue placeholder="타임존 선택" />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="Asia/Seoul">Asia/Seoul (KST)</SelectItem>
                      <SelectItem value="UTC">UTC</SelectItem>
                      <SelectItem value="America/New_York">America/New_York (EST)</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
                <Button className="w-full mt-4" onClick={handleCreateAccount}>
                  계정 생성 및 기본 구독 연결
                </Button>
              </CardContent>
            </Card>

            {/* 우측: 생성된 계정 목록 */}
            <Card>
              <CardHeader>
                <CardTitle>고객 목록</CardTitle>
                <CardDescription>시뮬레이션할 계정을 활성화(Activate) 해주세요.</CardDescription>
              </CardHeader>
              <CardContent>
                
                {visibleAccounts.length === 0 ? (
                  <p className="text-sm text-muted-foreground text-center py-10">생성된 활성 계정이 없습니다.</p>
                ) : (
                  <ul className="space-y-3 max-h-[300px] overflow-y-auto pr-2">
                    
                    {visibleAccounts.map((acc) => (
                      <li key={acc.id} className="flex items-center justify-between p-3 border rounded-lg bg-card">
                        <div>
                          <p className="font-semibold">{acc.name}</p>
                          <p className="text-xs text-muted-foreground">{acc.timezone}</p>
                        </div>
                        
                        <div className="flex gap-2">
                          <Button
                            variant={activeAccount?.id === acc.id ? "default" : "outline"}
                            size="sm"
                            onClick={() => handleSelectAccount(acc)}
                          >
                            {activeAccount?.id === acc.id ? "활성화됨" : "선택"}
                          </Button>
                          <Button
                            variant="destructive"
                            size="sm"
                            onClick={() => handleDeleteAccount(acc.id)}
                          >
                            삭제
                          </Button>
                        </div>
                      </li>
                    ))}
                  </ul>
                )}
              </CardContent>
            </Card>
          </div>
        </TabsContent>


        {/* 2번 탭: 실시간 트래픽 대시보드 */}
        <TabsContent value="dashboard">
          {activeTab !== "dashboard" ? null : !activeAccount ? (
            <Card className="border-dashed border-2 bg-muted/20 text-center py-20">
              <p className="text-xl font-semibold text-muted-foreground">1번 탭에서 시뮬레이션을 진행할 계정을 먼저 활성화해주세요.</p>
            </Card>
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-3 gap-6">

              {/* 좌측: 데이터 커스터마이징 컨트롤러 */}
              <Card className="col-span-1">
                <CardHeader>
                  <CardTitle>시뮬레이터 설정</CardTitle>
                  <CardDescription>발생할 API 데이터의 속성을 정의합니다.</CardDescription>
                </CardHeader>
                <CardContent className="space-y-4">
                  <div className="space-y-2">
                    <Label>사용 모델 (Endpoint)</Label>
                    <Select value={simConfig.endpoint} onValueChange={(val) => setSimConfig({...simConfig, endpoint: val})}>
                      <SelectTrigger><SelectValue /></SelectTrigger>
                      <SelectContent>
                        <SelectItem value="gpt-4-turbo">gpt-4-turbo (High Cost)</SelectItem>
                        <SelectItem value="gpt-3.5-turbo">gpt-3.5-turbo (Low Cost)</SelectItem>
                        <SelectItem value="claude-3-opus">claude-3-opus</SelectItem>
                      </SelectContent>
                    </Select>
                  </div>

                  <div className="grid grid-cols-2 gap-4">
                    <div className="space-y-2">
                      <Label>최소 토큰</Label>
                      <Input type="number" value={simConfig.minTokens} onChange={e => setSimConfig({...simConfig, minTokens: Number(e.target.value)})} />
                    </div>
                    <div className="space-y-2">
                      <Label>최대 토큰</Label>
                      <Input type="number" value={simConfig.maxTokens} onChange={e => setSimConfig({...simConfig, maxTokens: Number(e.target.value)})} />
                    </div>
                  </div>

                  <div className="space-y-2 pt-4 border-t">
                    <Label className="text-destructive font-bold">🚨 이상 감지 기준 (Tokens)</Label>
                    <p className="text-xs text-muted-foreground mb-2">이 수치를 초과하는 단일 요청은 어뷰징/디도스로 플래그 처리됩니다.</p>
                    <Input type="number" value={simConfig.anomalyThreshold} onChange={e => setSimConfig({...simConfig, anomalyThreshold: Number(e.target.value)})} />
                  </div>

                  <div className="space-y-2 pt-6">
                    <Button className="w-full" variant="secondary" onClick={() => triggerTraffic(false)}>
                      단일 트래픽 1건 발생
                    </Button>
                    <Button
                      className="w-full"
                      variant={isSimulating ? "default" : "outline"}
                      onClick={() => { setIsSimulating(!isSimulating); setIsAnomalySimulating(false); }}
                    >
                      {isSimulating ? "🛑 일반 트래픽 중지" : "▶️ 지속 트래픽 쏘기 (1초)"}
                    </Button>
                    <Button
                      className="w-full"
                      variant={isAnomalySimulating ? "destructive" : "outline"}
                      onClick={() => { setIsAnomalySimulating(!isAnomalySimulating); setIsSimulating(false); }}
                    >
                      {isAnomalySimulating ? "🛑 이상치 폭격 중지" : "🔥 이상치 지속 폭격 (디도스)"}
                    </Button>
                  </div>
                </CardContent>
              </Card>

              {/* 우측: 실시간 차트 및 요금 모니터링 */}
              <Card className="col-span-2">
                <CardHeader>
                  <CardTitle>실시간 모니터링: {activeAccount.name}</CardTitle>
                  <CardDescription>토큰 사용량 및 이번 달 누적 예상 요금 (단위: ₩)</CardDescription>
                </CardHeader>
                <CardContent>
                  {anomalyAlert && (
                    <div className="mb-4 p-3 bg-red-100 border border-red-400 text-red-700 rounded-md font-bold text-sm animate-in fade-in slide-in-from-top-2">
                      {anomalyAlert}
                    </div>
                  )}

                  <div className="grid grid-cols-2 gap-4 text-center mb-6">
                    <div className="p-4 bg-muted rounded-lg border flex flex-col justify-center">
                      <p className="text-sm text-muted-foreground mb-1">최근 요청 토큰 수 ({simConfig.endpoint})</p>
                      <p className="text-2xl font-bold">
                        {filteredChartData.length > 0 ? filteredChartData[filteredChartData.length - 1].tokens.toLocaleString() : 0}
                      </p>
                    </div>
                    <div className="p-4 bg-primary/5 rounded-lg border border-primary/20 relative overflow-hidden">
                      <div className="absolute top-0 right-0 bg-primary/20 text-primary text-[10px] font-bold px-2 py-1 rounded-bl-lg">
                        가계산 (Estimate)
                      </div>
                      <p className="text-sm text-primary font-medium mb-1">이번 달 누적 요금</p>
                      <p className="text-3xl font-extrabold text-primary mb-1">
                        ₩ {Math.floor(monthlyCost).toLocaleString()}
                      </p>
                      <p className="text-[11px] text-muted-foreground leading-tight">
                        * 토큰당 0.2원이 곱해진 단순 예상치입니다.<br/>
                        * 실제 청구액(할인/누진제 적용)은 3번 탭을 확인하세요.
                      </p>
                    </div>
                  </div>

                  <h3 className="text-sm font-semibold mb-2">실시간 트래픽 ({simConfig.endpoint})</h3>
                  <div className="h-[200px] w-full mb-8">
                    <ResponsiveContainer width="100%" height="100%">
                      <LineChart data={filteredChartData}>
                        <CartesianGrid strokeDasharray="3 3" vertical={false} />
                        <XAxis dataKey="time" tick={{fontSize: 11}} />
                        <YAxis tick={{fontSize: 11}} width={40} />
                        <Tooltip />
                        <ReferenceLine y={simConfig.anomalyThreshold} stroke="#dc2626" strokeDasharray="3 3" label={{ position: "top", value: "경고 기준", fill: "#dc2626", fontSize: 10 }} />
                        <Line type="monotone" dataKey="tokens" stroke="#2563eb" strokeWidth={2} isAnimationActive={false} dot={false} />
                      </LineChart>
                    </ResponsiveContainer>
                  </div>

                  <div className="flex items-center justify-between mb-2">
                    <h3 className="text-sm font-semibold">기간별 사용량 추이</h3>
                    <div className="flex gap-1 bg-muted p-1 rounded-md">
                      {(["hour", "day", "week", "month"] as TimeFrame[]).map((frame) => (
                        <button
                          key={frame}
                          type="button"
                          onClick={() => setTimeFrame(frame)}
                          className={`text-xs px-3 py-1 rounded-sm ${timeFrame === frame ? "bg-background shadow-sm font-bold" : "text-muted-foreground hover:text-foreground"}`}
                        >
                          {frame === "hour" ? "시간" : frame === "day" ? "일" : frame === "week" ? "주" : "월"}
                        </button>
                      ))}
                    </div>
                  </div>
                  <div className="h-[150px] w-full">
                    <ResponsiveContainer width="100%" height="100%">
                      <BarChart data={historicalData}>
                        <CartesianGrid strokeDasharray="3 3" vertical={false} />
                        <XAxis dataKey="label" tick={{fontSize: 11}} />
                        <YAxis tick={{fontSize: 11}} width={40} />
                        <Tooltip cursor={{fill: "transparent"}} />
                        <Bar dataKey="tokens" fill="#94a3b8" radius={[4, 4, 0, 0]} />
                      </BarChart>
                    </ResponsiveContainer>
                  </div>
                </CardContent>
              </Card>

            </div>
          )}
        </TabsContent>

        <TabsContent value="invoice">
          {!activeAccount ? (
            <Card className="border-dashed border-2 bg-muted/20 text-center py-20">
              <p className="text-xl font-semibold text-muted-foreground">1번 탭에서 정산할 계정을 먼저 활성화해주세요.</p>
            </Card>
          ) : (
            <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
              <Card className="lg:col-span-1">
                <CardHeader>
                  <CardTitle>정산 컨트롤</CardTitle>
                  <CardDescription>기본 구독은 계정 생성 시 자동 연결되며, 이 영역에서는 관리자 권한으로 보정할 수 있습니다.</CardDescription>
                </CardHeader>
                <CardContent className="space-y-5">
                  <div className="space-y-2">
                    <Label htmlFor="invoice-month">정산 대상 월</Label>
                    <Input
                      id="invoice-month"
                      type="month"
                      value={invoiceMonth}
                      onChange={(event) => handleInvoiceMonthChange(event.target.value)}
                    />
                  </div>

                  <div className="rounded-lg border p-4 space-y-3">
                    <div className="flex items-start justify-between gap-3">
                      <div>
                        <p className="text-sm font-semibold">활성 구독</p>
                        <p className="text-xs text-muted-foreground">
                          {activeSubscription
                            ? formatPeriod(activeSubscription.current_period_start, activeSubscription.current_period_end)
                            : "선택 월에 활성 구독이 없습니다. 관리자 권한으로 연결할 수 있습니다."}
                        </p>
                      </div>
                      <span className={`rounded-full px-2 py-1 text-xs font-semibold ${activeSubscription ? "bg-green-100 text-green-800" : "bg-muted text-muted-foreground"}`}>
                        {activeSubscription ? "Active" : "None"}
                      </span>
                    </div>
                    <div className="grid grid-cols-2 gap-2">
                      <Button variant="secondary" onClick={handleEnsureSubscription} disabled={Boolean(activeSubscription) || isBillingLoading}>
                        관리자 구독 연결
                      </Button>
                      <Button variant="outline" onClick={handleCancelActiveSubscription} disabled={!activeSubscription || isBillingLoading}>
                        관리자 구독 취소
                      </Button>
                    </div>
                  </div>

                  <div className="rounded-lg border p-4 space-y-3">
                    <div>
                      <p className="text-sm font-semibold">월 청구서 생성</p>
                      <p className="text-xs text-muted-foreground">DB 함수가 사용량 집계, 라인아이템, 원장 차감을 한 번에 처리합니다.</p>
                    </div>
                    <Button className="w-full" onClick={handleGenerateInvoice} disabled={isGeneratingInvoice || isBillingLoading}>
                      {isGeneratingInvoice ? "생성 중..." : "정산 엔진 실행"}
                    </Button>
                  </div>

                  <div className="rounded-lg border p-4 space-y-3">
                    <div>
                      <p className="text-sm font-semibold">크레딧 수동 충전</p>
                      <p className="text-xs text-muted-foreground">현재 잔액: <span className="font-bold text-foreground">{formatCurrency(currentBalance)}</span></p>
                    </div>
                    <div className="grid grid-cols-[1fr_auto] gap-2">
                      <Input
                        type="number"
                        min={1}
                        value={creditTopUpAmount}
                        onChange={(event) => setCreditTopUpAmount(Number(event.target.value))}
                      />
                      <Button variant="outline" onClick={handleCreditTopUp}>
                        충전
                      </Button>
                    </div>
                  </div>

                  <Button variant="ghost" className="w-full" onClick={() => loadBillingData(activeAccount.id, invoiceMonth)} disabled={isBillingLoading}>
                    {isBillingLoading ? "새로고침 중..." : "정산 데이터 새로고침"}
                  </Button>

                  {billingMessage && (
                    <div className="rounded-lg border bg-muted/40 p-3 text-sm text-muted-foreground whitespace-pre-wrap">
                      {billingMessage}
                    </div>
                  )}
                </CardContent>
              </Card>

              <div className="lg:col-span-2 space-y-6">
                <Card>
                  <CardHeader>
                    <CardTitle>청구서 목록</CardTitle>
                    <CardDescription>{activeAccount.name} 계정의 생성된 청구서와 라인아이템입니다.</CardDescription>
                  </CardHeader>
                  <CardContent>
                    {invoices.length === 0 ? (
                      <div className="text-center py-12 text-sm text-muted-foreground">
                        아직 생성된 청구서가 없습니다. 트래픽을 발생시킨 뒤 정산 엔진을 실행해보세요.
                      </div>
                    ) : (
                      <div className="space-y-4">
                        {invoices.map((invoice) => {
                          const items = lineItemsByInvoiceId.get(invoice.id) ?? []
                          return (
                            <div key={invoice.id} className="rounded-lg border p-4">
                              <div className="flex flex-col gap-3 md:flex-row md:items-start md:justify-between">
                                <div className="space-y-1">
                                  <div className="flex items-center gap-2">
                                    <p className="font-semibold">{formatCurrency(invoice.total_amount)}</p>
                                    <span className="rounded-full bg-primary/10 px-2 py-1 text-xs font-semibold text-primary">{invoice.status}</span>
                                  </div>
                                  <p className="text-xs text-muted-foreground">{formatPeriod(invoice.billing_period_start, invoice.billing_period_end)}</p>
                                  <p className="font-mono text-[11px] text-muted-foreground">{invoice.id}</p>
                                </div>
                                <div className="flex flex-wrap gap-2">
                                  <div className="w-full text-xs font-medium text-muted-foreground md:text-right">
                                    관리자 권한으로 상태 임의 변경 가능
                                  </div>
                                  <Button size="sm" variant="secondary" onClick={() => handleUpdateInvoiceStatus(invoice.id, "Paid")}>
                                    Paid
                                  </Button>
                                  <Button size="sm" variant="outline" onClick={() => handleUpdateInvoiceStatus(invoice.id, "Open")}>
                                    Open
                                  </Button>
                                  <Button size="sm" variant="destructive" onClick={() => handleUpdateInvoiceStatus(invoice.id, "Void")}>
                                    Void
                                  </Button>
                                </div>
                              </div>

                              <div className="mt-4 overflow-hidden rounded-md border">
                                <div className="grid grid-cols-[1fr_120px_120px] bg-muted px-3 py-2 text-xs font-semibold text-muted-foreground">
                                  <span>항목</span>
                                  <span className="text-right">수량</span>
                                  <span className="text-right">금액</span>
                                </div>
                                {items.length === 0 ? (
                                  <div className="px-3 py-4 text-sm text-muted-foreground">라인아이템이 없습니다.</div>
                                ) : (
                                  items.map((item) => (
                                    <div key={item.id} className="grid grid-cols-[1fr_120px_120px] border-t px-3 py-2 text-sm">
                                      <span>{metricNameById.get(item.metric_id) ?? item.metric_id}</span>
                                      <span className="text-right tabular-nums">{Number(item.quantity).toLocaleString()}</span>
                                      <span className="text-right tabular-nums">{formatCurrency(item.amount)}</span>
                                    </div>
                                  ))
                                )}
                              </div>
                            </div>
                          )
                        })}
                      </div>
                    )}
                  </CardContent>
                </Card>

                <Card>
                  <CardHeader>
                    <CardTitle>크레딧 원장</CardTitle>
                    <CardDescription>청구서 생성 시 차감되고, 수동 충전 시 증가하는 잔액 흐름입니다.</CardDescription>
                  </CardHeader>
                  <CardContent>
                    {creditLedgers.length === 0 ? (
                      <div className="text-center py-10 text-sm text-muted-foreground">원장 기록이 없습니다.</div>
                    ) : (
                      <div className="overflow-hidden rounded-md border">
                        <div className="grid grid-cols-[1fr_120px_120px] bg-muted px-3 py-2 text-xs font-semibold text-muted-foreground">
                          <span>거래</span>
                          <span className="text-right">금액</span>
                          <span className="text-right">잔액</span>
                        </div>
                        {creditLedgers.map((ledger) => (
                          <div key={ledger.id} className="grid grid-cols-[1fr_120px_120px] border-t px-3 py-2 text-sm">
                            <div className="min-w-0">
                              <p className="font-medium">{ledger.transaction_type}</p>
                              <p className="truncate font-mono text-[11px] text-muted-foreground">
                                {formatDateTime(ledger.created_at)} · {ledger.reference_type}:{ledger.reference_id ?? "-"}
                              </p>
                            </div>
                            <span className="text-right tabular-nums">{formatCurrency(ledger.amount)}</span>
                            <span className="text-right tabular-nums font-semibold">{formatCurrency(ledger.running_balance)}</span>
                          </div>
                        ))}
                      </div>
                    )}
                  </CardContent>
                </Card>
              </div>
            </div>
          )}
        </TabsContent>
      </Tabs>
    </div>
  )
}
