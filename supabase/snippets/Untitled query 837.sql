-- Products 테이블에 대한 읽기(SELECT) 권한을 모두에게 개방
ALTER TABLE Products ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Enable read access for all users" ON Products FOR SELECT USING (true);