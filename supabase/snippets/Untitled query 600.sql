-- 1. 코어 및 계정 관리 도메인
CREATE TABLE Accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    parent_account_id UUID REFERENCES Accounts(id) ON DELETE SET NULL,
    name TEXT NOT NULL,
    timezone TEXT NOT NULL DEFAULT 'UTC',
    status TEXT NOT NULL
);

-- 2. 사용량 이벤트 도메인
CREATE TABLE Usage_Events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    idempotency_key TEXT UNIQUE NOT NULL,
    account_id UUID NOT NULL REFERENCES Accounts(id) ON DELETE CASCADE,
    event_name TEXT NOT NULL,
    timestamp TIMESTAMPTZ NOT NULL,
    properties JSONB DEFAULT '{}'::jsonb,
    ingested_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 수평 분할 아카이브 테이블 (운영 데이터와 분리 보관, 외래키 제약 생략 가능)
CREATE TABLE Usage_Events_Archive (
    id UUID PRIMARY KEY,
    idempotency_key TEXT,
    account_id UUID,
    event_name TEXT,
    timestamp TIMESTAMPTZ,
    properties JSONB,
    ingested_at TIMESTAMPTZ
);

-- 3. 집계 지표 도메인
CREATE TABLE Billable_Metrics (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    event_name TEXT NOT NULL,
    property_key TEXT,
    aggregation_type TEXT NOT NULL, -- SUM, COUNT, MAX, UNIQUE_COUNT 등
    group_keys TEXT[],              -- 다차원 필터링 키 배열 (예: ['region', 'model'])
    sql_definition TEXT
);

-- 4. 가격 책정 및 요금표 도메인
CREATE TABLE Products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL
);

CREATE TABLE Rate_Cards (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID NOT NULL REFERENCES Products(id) ON DELETE CASCADE
);

CREATE TABLE Prices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rate_card_id UUID NOT NULL REFERENCES Rate_Cards(id) ON DELETE CASCADE,
    metric_id UUID NOT NULL REFERENCES Billable_Metrics(id) ON DELETE CASCADE,
    pricing_model TEXT NOT NULL, -- Standard, Tiered, Package 등
    effective_start TIMESTAMPTZ NOT NULL,
    effective_end TIMESTAMPTZ
);

-- 가격 티어 (수직 분할 부분 집합 테이블)
CREATE TABLE Price_Tiers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    price_id UUID NOT NULL REFERENCES Prices(id) ON DELETE CASCADE,
    first_unit NUMERIC NOT NULL DEFAULT 0,
    last_unit NUMERIC, -- NULL일 경우 '초과' 혹은 '무제한'을 의미
    unit_amount NUMERIC NOT NULL DEFAULT 0,
    flat_amount NUMERIC NOT NULL DEFAULT 0
);

-- 가격 차원 (수직 분할 부분 집합 테이블)
CREATE TABLE Price_Dimensions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    price_id UUID NOT NULL REFERENCES Prices(id) ON DELETE CASCADE,
    dimension_key TEXT NOT NULL,
    dimension_value TEXT NOT NULL
);

-- 5. 구독 및 계약 도메인
CREATE TABLE Subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id UUID NOT NULL REFERENCES Accounts(id) ON DELETE CASCADE,
    rate_card_id UUID NOT NULL REFERENCES Rate_Cards(id) ON DELETE CASCADE,
    billing_interval TEXT NOT NULL, -- Monthly, Yearly
    current_period_start TIMESTAMPTZ NOT NULL,
    current_period_end TIMESTAMPTZ NOT NULL,
    status TEXT NOT NULL
);

-- 6. 청구 및 크레딧 장부 도메인
CREATE TABLE Invoices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id UUID NOT NULL REFERENCES Accounts(id) ON DELETE CASCADE,
    subtotal NUMERIC NOT NULL DEFAULT 0,
    total_amount NUMERIC NOT NULL DEFAULT 0,
    status TEXT NOT NULL -- Draft, Finalized, Paid, Overdue 등
);

-- 청구 항목 연결 테이블 (다중값 필드 해소)
CREATE TABLE Invoice_Line_Items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    invoice_id UUID NOT NULL REFERENCES Invoices(id) ON DELETE CASCADE,
    metric_id UUID NOT NULL REFERENCES Billable_Metrics(id) ON DELETE CASCADE,
    quantity NUMERIC NOT NULL DEFAULT 0,
    amount NUMERIC NOT NULL DEFAULT 0
);

-- 크레딧 변동 장부 테이블
CREATE TABLE Credit_Ledgers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id UUID NOT NULL REFERENCES Accounts(id) ON DELETE CASCADE,
    transaction_type TEXT NOT NULL, -- Grant, Deduct, Void, Expire 등
    amount NUMERIC NOT NULL DEFAULT 0,
    running_balance NUMERIC NOT NULL DEFAULT 0,
    reference_id TEXT -- 변동을 일으킨 원인 식별용 (Invoice ID 또는 Event ID 등)
);