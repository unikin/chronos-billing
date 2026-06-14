BEGIN;

-- 기존 이름 기준 FK 제거
ALTER TABLE Usage_Events DROP CONSTRAINT IF EXISTS usage_events_account_id_fkey;
ALTER TABLE Subscriptions DROP CONSTRAINT IF EXISTS subscriptions_account_id_fkey;
ALTER TABLE Invoices DROP CONSTRAINT IF EXISTS invoices_account_id_fkey;
ALTER TABLE Credit_Ledgers DROP CONSTRAINT IF EXISTS credit_ledgers_account_id_fkey;

-- FK 재설정
ALTER TABLE Usage_Events
  ADD CONSTRAINT usage_events_account_id_fkey
  FOREIGN KEY (account_id) REFERENCES Accounts(id) ON DELETE RESTRICT;

ALTER TABLE Subscriptions
  ADD CONSTRAINT subscriptions_account_id_fkey
  FOREIGN KEY (account_id) REFERENCES Accounts(id) ON DELETE RESTRICT;

ALTER TABLE Invoices
  ADD CONSTRAINT invoices_account_id_fkey
  FOREIGN KEY (account_id) REFERENCES Accounts(id) ON DELETE RESTRICT;

ALTER TABLE Credit_Ledgers
  ALTER COLUMN account_id SET NOT NULL,
  ALTER COLUMN amount TYPE NUMERIC(18, 2),
  ALTER COLUMN running_balance TYPE NUMERIC(18, 2),
  ADD COLUMN IF NOT EXISTS reference_type VARCHAR(50),
  ADD COLUMN IF NOT EXISTS currency VARCHAR(3) DEFAULT 'KRW' NOT NULL,
  ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL;

UPDATE Credit_Ledgers
SET reference_type = 'Manual_Adjustment'
WHERE reference_type IS NULL;

ALTER TABLE Credit_Ledgers
  ALTER COLUMN reference_type SET NOT NULL,
  ADD CONSTRAINT credit_ledgers_account_id_fkey
  FOREIGN KEY (account_id) REFERENCES Accounts(id) ON DELETE RESTRICT;

-- 기존 check/unique 제거 후 재생성
ALTER TABLE Credit_Ledgers DROP CONSTRAINT IF EXISTS credit_ledgers_amount_check;
ALTER TABLE Credit_Ledgers DROP CONSTRAINT IF EXISTS credit_ledgers_currency_check;
ALTER TABLE Price_Tiers DROP CONSTRAINT IF EXISTS tiers_unit_check;
ALTER TABLE Invoices DROP CONSTRAINT IF EXISTS invoice_amount_check;
ALTER TABLE Invoice_Line_Items DROP CONSTRAINT IF EXISTS line_item_amount_check;
ALTER TABLE Prices DROP CONSTRAINT IF EXISTS prices_date_check;
ALTER TABLE Accounts DROP CONSTRAINT IF EXISTS accounts_parent_check;
ALTER TABLE Accounts DROP CONSTRAINT IF EXISTS accounts_status_check;
ALTER TABLE Subscriptions DROP CONSTRAINT IF EXISTS subs_status_check;
ALTER TABLE Invoices DROP CONSTRAINT IF EXISTS invoices_status_check;
ALTER TABLE Price_Tiers DROP CONSTRAINT IF EXISTS tiers_unique_start;

ALTER TABLE Credit_Ledgers
  ADD CONSTRAINT credit_ledgers_amount_check CHECK (amount >= 0),
  ADD CONSTRAINT credit_ledgers_currency_check CHECK (currency ~ '^[A-Z]{3}$');

ALTER TABLE Price_Tiers
  ALTER COLUMN unit_amount TYPE NUMERIC(18, 2),
  ALTER COLUMN flat_amount TYPE NUMERIC(18, 2),
  ADD CONSTRAINT tiers_unit_check CHECK (
    first_unit >= 0
    AND unit_amount >= 0
    AND flat_amount >= 0
    AND (last_unit IS NULL OR first_unit <= last_unit)
  ),
  ADD CONSTRAINT tiers_unique_start UNIQUE (price_id, first_unit);

ALTER TABLE Invoices
  ALTER COLUMN subtotal TYPE NUMERIC(18, 2),
  ALTER COLUMN total_amount TYPE NUMERIC(18, 2),
  ADD CONSTRAINT invoice_amount_check CHECK (subtotal >= 0 AND total_amount >= 0),
  ADD CONSTRAINT invoices_status_check CHECK (status IN ('Draft', 'Open', 'Paid', 'Void', 'Uncollectible'));

ALTER TABLE Invoice_Line_Items
  ALTER COLUMN amount TYPE NUMERIC(18, 2),
  ADD CONSTRAINT line_item_amount_check CHECK (amount >= 0 AND quantity >= 0);

ALTER TABLE Prices
  ADD CONSTRAINT prices_date_check CHECK (effective_end IS NULL OR effective_start < effective_end);

ALTER TABLE Accounts
  ADD CONSTRAINT accounts_parent_check CHECK (parent_account_id IS NULL OR parent_account_id <> id),
  ADD CONSTRAINT accounts_status_check CHECK (status IN ('Active', 'Inactive', 'Suspended', 'Archived'));

ALTER TABLE Subscriptions
  ADD CONSTRAINT subs_status_check CHECK (status IN ('Active', 'Canceled', 'Past_Due', 'Trial'));

COMMIT;