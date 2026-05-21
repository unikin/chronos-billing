// src/app/page.tsx
import { supabase } from '../../utils/supabase'

export default async function Home() {
  // 2. 이미 supabase 객체가 타입을 알고 있으므로, 반환되는 products 변수에 자동으로 타입이 적용됩니다.
  const { data: products, error } = await supabase
    .from('products') 
    .select('*')

  if (error) {
    console.error('데이터를 가져오는데 실패했습니다:', error)
    return <div>에러가 발생했습니다.</div>
  }

  return (
    <div style={{ padding: '2rem' }}>
      <h1>Chronos-Billing 상품 목록</h1>
      <ul>
        {/* product의 타입을 별도로 명시하지 않아도 name, id 등이 완벽히 자동완성됩니다 */}
        {products?.map((product) => (
          <li key={product.id}>
            <strong>{product.name}</strong> (ID: {product.id})
          </li>
        ))}
      </ul>
    </div>
  )
}