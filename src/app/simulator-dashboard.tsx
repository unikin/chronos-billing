"use client"

import { useState } from "react"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import type { Database } from "../../types/supabase"
import { createSupabaseClient } from "../../utils/supabase"

type Account = Database["public"]["Tables"]["accounts"]["Row"]

type SimulatorDashboardProps = {
  initialAccounts: Account[]
}

export function SimulatorDashboard({ initialAccounts }: SimulatorDashboardProps) {
  // 전역 상태 관리
  const [accounts, setAccounts] = useState<Account[]>(initialAccounts)
  const [activeAccount, setActiveAccount] = useState<Account | null>(null)

  // 폼 입력 상태
  const [newAccountName, setNewAccountName] = useState("")
  const [newTimezone, setNewTimezone] = useState("Asia/Seoul")

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

    setAccounts((currentAccounts) => [data, ...currentAccounts])
    setNewAccountName("")
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
    if (activeAccount?.id === accountId) setActiveAccount(null)
  }

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

      <Tabs defaultValue="account" className="w-full">
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
                <CardDescription>과금 시뮬레이션을 진행할 조직을 생성합니다.</CardDescription>
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
                  계정 생성 및 DB 저장
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
                            onClick={() => setActiveAccount(acc)}
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

        {/* 탭 2, 3 생략 (이전 코드와 동일하게 유지) */}
        <TabsContent value="dashboard"><Card><CardContent>준비 중...</CardContent></Card></TabsContent>
        <TabsContent value="invoice"><Card><CardContent>준비 중...</CardContent></Card></TabsContent>
      </Tabs>
    </div>
  )
}
