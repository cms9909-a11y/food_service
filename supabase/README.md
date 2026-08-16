# Supabase 연결하기

식당 데이터를 HTML 안에 박아두지 않고 Supabase에서 읽어옵니다.
이제 식당을 추가·수정하려면 **Supabase 대시보드의 Table Editor**에서 고치면 되고,
코드는 건드리지 않아도 됩니다.

## 1. 프로젝트 만들기

[supabase.com](https://supabase.com) 에서 프로젝트를 하나 만듭니다. 리전은 `Northeast Asia (Seoul)` 이 가장 빠릅니다.

## 2. 테이블 만들기

대시보드 좌측 **SQL Editor** → `New query` 에 [`schema.sql`](./schema.sql) 내용을 붙여넣고 **Run**.

테이블 하나(`restaurants`)와 인덱스, 그리고 **RLS 정책**이 생성됩니다.

## 3. 데이터 넣기

같은 방식으로 [`seed.sql`](./seed.sql) 을 붙여넣고 **Run**. 62곳이 들어갑니다.

> `seed.sql` 은 맨 앞에서 `truncate` 를 하므로, **다시 실행하면 기존 데이터가 전부 지워지고 초기 62곳으로 되돌아갑니다.**
> 대시보드에서 수정한 내용이 있다면 다시 실행하지 마세요.

## 4. 연결 정보 넣기

**Project Settings → API** 에서 두 값을 복사해 `index.html` 상단에 붙여넣습니다.

```js
const SUPABASE_URL      = 'https://xxxxxxxx.supabase.co';  // Project URL
const SUPABASE_ANON_KEY = 'eyJhbGci...';                   // anon public
```

### anon 키를 공개 저장소에 올려도 되나요

**됩니다.** anon 키는 브라우저에 노출되는 것을 전제로 설계된 공개 키입니다.
보안은 키를 숨기는 게 아니라 **RLS 정책**이 담당합니다.

`schema.sql` 은 이렇게 설정합니다.

- `select` 정책만 만듭니다 → 누구나 **읽기만** 가능
- `insert` / `update` / `delete` 정책은 만들지 않습니다 → anon 키로는 **데이터를 바꿀 수 없음**

절대 올리면 안 되는 것은 **`service_role` 키**입니다. 이 키는 RLS를 무시합니다.
`index.html` 에는 반드시 `anon public` 키만 넣으세요.

## 데이터 다루기

| 하고 싶은 일 | 방법 |
|---|---|
| 식당 추가 | Table Editor → `restaurants` → Insert row |
| 가격·영업시간 수정 | 해당 행을 직접 편집 |
| 식당 삭제 | 행 삭제 |
| 정렬 순서 변경 | `sort_order` 값 수정 (오름차순 정렬) |

수정하면 **새로고침만으로 사이트에 바로 반영**됩니다. 재배포가 필요 없습니다.

### 입력 규칙

- `price_band` — `A`(1만원 이하) / `B`(1~2만원) / `C`(2만원 이상), **모두 1인당 기준**.
  나눠 먹는 메뉴는 인원으로 나눠 환산합니다. 모르면 **비워 두세요**(추정 금지).
- `hours` — 모르면 비워 둡니다. 예시:
  ```json
  {"open":"11:00","close":"21:00","closed":[0],"brk":["15:00","17:00"]}
  ```
  - `closed` 는 요일 배열, **0이 일요일**입니다
  - 자정을 넘겨 영업하면 24를 더합니다. 새벽 1시 마감 → `"25:00"`
  - 브레이크타임이 없으면 `"brk": null`
- `dish` — 필터 칩과 글자가 정확히 같아야 검색됩니다.
  `백반·정식` `덮밥` `돈까스` `면·국수` `중화요리` `파스타·피자` `버거` `족발·보쌈·전` `곱창·구이` `찜닭` `빵·커피`
  새 값을 쓰려면 `index.html` 의 `dishChips` 에도 칩을 추가해야 합니다.
- `source` — `학교 공식` / `다이닝코드` / `구글 지도` / `매장 SNS`

## 문제가 생기면

| 화면 | 원인 |
|---|---|
| "Supabase 연결 정보가 설정되지 않았어요" | `index.html` 상단 두 값이 아직 자리표시자 |
| "불러오지 못했어요 · Supabase 응답 401" | anon 키가 틀림 |
| "불러오지 못했어요 · Supabase 응답 404" | 테이블이 없음 → `schema.sql` 실행 |
| "등록된 식당이 없어요" | 테이블은 있는데 비어 있음 → `seed.sql` 실행 |
| 응답 200인데 0곳 | RLS는 켜졌는데 select 정책이 없음 → `schema.sql` 재실행 |
