-- 성균관대 맛집 찾기 · 테이블 스키마
-- Supabase 대시보드 > SQL Editor 에 붙여넣고 실행하세요.
-- 실행 순서: schema.sql → seed.sql

create table if not exists public.restaurants (
  id          bigint generated always as identity primary key,
  sort_order  integer not null default 0,          -- 기본 정렬(캠퍼스·교내순) 유지용

  name        text not null,
  campus      text not null check (campus in ('자연과학캠퍼스','인문사회과학캠퍼스')),
  area        text not null check (area in ('교내','교외')),
  dish        text not null,                        -- 주 필터: 무엇을 먹을까
  cuisine     text not null,                        -- 카드 표시용 국적 분류
  serving     text not null check (serving in ('1인','나눠먹기')),

  -- 가격: 1인당 예상 지출 기준. 나눠 먹는 메뉴는 인원으로 나눠 환산한 값.
  -- null 이면 "가격 정보 미확인" (임의 추정 금지)
  price_band  text check (price_band in ('A','B','C')),
  price_label text not null,

  -- 영업시간. null 이면 미확인.
  -- 예: {"open":"11:00","close":"25:00","closed":[0],"brk":["15:00","17:00"]}
  --  - close 가 24:00 을 넘으면 자정 넘김 영업 (25:00 = 새벽 1시)
  --  - closed 는 요일 배열, 0=일요일
  --  - brk 는 브레이크타임 [시작, 끝], 없으면 null
  hours       jsonb,

  -- 출처: 학교 공식 | 다이닝코드 | 구글 지도 | 매장 SNS
  source      text not null,

  lat         double precision,
  lng         double precision,

  menu        text not null,
  location    text not null,
  description text not null,
  tags        text[] not null default '{}',

  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

comment on column public.restaurants.price_band is 'A=1만원 이하, B=1~2만원, C=2만원 이상. 모두 1인당 기준. null=미확인';
comment on column public.restaurants.hours is 'null=미확인. close>24:00은 자정 넘김. closed 0=일요일';

create index if not exists restaurants_campus_area_idx on public.restaurants (campus, area);
create index if not exists restaurants_dish_idx        on public.restaurants (dish);
create index if not exists restaurants_sort_idx        on public.restaurants (sort_order);

-- updated_at 자동 갱신
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists restaurants_touch_updated_at on public.restaurants;
create trigger restaurants_touch_updated_at
  before update on public.restaurants
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------
-- 행 수준 보안(RLS)
-- anon 키는 브라우저에 그대로 노출되므로 반드시 켜 두어야 합니다.
-- 읽기만 허용하고, 쓰기는 대시보드(service_role)에서만 하도록 둡니다.
-- ---------------------------------------------------------------
alter table public.restaurants enable row level security;

drop policy if exists "restaurants are publicly readable" on public.restaurants;
create policy "restaurants are publicly readable"
  on public.restaurants
  for select
  to anon, authenticated
  using (true);

-- insert/update/delete 정책은 만들지 않습니다.
-- → anon 키로는 데이터를 바꿀 수 없습니다.
