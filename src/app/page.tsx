// src/app/page.tsx
import { createSupabaseClient } from '../../utils/supabase'

export default async function Home() {
  const supabase = createSupabaseClient()

  if (!supabase) {
    return (
      <main style={{ padding: '2rem' }}>
        <h1>Chronos-Billing 상품 목록</h1>
        <p>
          Supabase 환경변수 NEXT_PUBLIC_SUPABASE_URL 또는
          NEXT_PUBLIC_SUPABASE_ANON_KEY가 설정되지 않았습니다.
        </p>
      </main>
    )
  }

  const { data: products, error } = await supabase
    .from('products') 
    .select('*')

  if (error) {
    console.error('데이터를 가져오는데 실패했습니다:', error)
    return <div>에러가 발생했습니다.</div>
  }

  return (
    <main style={{ padding: '2rem' }}>
      <h1>Chronos-Billing 상품 목록</h1>
      <ul>
        {products?.map((product) => (
          <li key={product.id}>
            <strong>{product.name}</strong> (ID: {product.id})
          </li>
        ))}
      </ul>
    </main>
  )
}
