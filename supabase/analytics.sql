-- 검색 로그 · 사용자가 필터로 찾은 결과를 쌓는다
-- schema.sql / seed.sql 을 실행한 뒤 이 파일을 실행하세요.
--
-- 개인정보는 저장하지 않습니다. session_id 는 브라우저 탭 세션마다
-- 새로 만들어지는 임의 문자열이고, 탭을 닫으면 사라집니다.

create table if not exists public.search_logs (
  id           bigint generated always as identity primary key,
  created_at   timestamptz not null default now(),

  -- 'search'   = 필터로 검색한 순간
  -- 'pick'     = 그 결과 중 랜덤 추천으로 한 곳이 뽑힌 순간
  -- 'feedback' = "원하는 식당을 찾으셨나요?" 에 답한 순간
  kind         text not null check (kind in ('search','pick','feedback')),

  -- 그때 걸려 있던 필터 조건
  -- 예: {"campus":["자연과학캠퍼스"],"area":[],"dish":["돈까스"],
  --      "serving":[],"price":["A"],"openNow":true}
  filters      jsonb not null,

  result_count integer not null check (result_count >= 0),
  result_ids   bigint[] not null default '{}',   -- 결과로 나온 식당 id
  picked_id    bigint references public.restaurants(id) on delete set null,
  found        boolean,   -- kind='feedback' 일 때만: 원하는 식당을 찾았는지

  session_id   text,

  -- found 는 feedback 행에만 있어야 한다.
  -- 이 조건이 보장되어야 stat_feedback 의 응답 수와 예/아니오 합이 일치한다.
  constraint search_logs_found_only_on_feedback
    check ((kind = 'feedback') = (found is not null)),

  -- picked_id 는 pick 행에만 있어야 한다.
  constraint search_logs_picked_only_on_pick
    check (kind = 'pick' or picked_id is null)
);

comment on table  public.search_logs is '필터 검색·랜덤 추천·만족도 응답 기록. 개인정보 없음';
comment on column public.search_logs.result_ids is '검색 결과로 화면에 나온 식당 id 목록';
comment on column public.search_logs.picked_id is 'kind=pick 일 때 랜덤으로 뽑힌 식당';
comment on column public.search_logs.found is 'kind=feedback 일 때 원하는 식당을 찾았는지 여부';

create index if not exists search_logs_created_idx on public.search_logs (created_at desc);
create index if not exists search_logs_kind_idx    on public.search_logs (kind);

-- 집계 뷰가 kind로 걸러 읽으므로 해당 행만 담는 부분 인덱스를 둔다
create index if not exists search_logs_picked_idx on public.search_logs (picked_id)
  where kind = 'pick';
create index if not exists search_logs_found_idx  on public.search_logs (found)
  where kind = 'feedback';

-- ---------------------------------------------------------------
-- RLS · 넣기만 되고 읽기는 안 되게
--   - anon 키는 브라우저에 노출되므로 select 를 열면 누구나 로그를 다 볼 수 있습니다.
--   - insert 정책만 만들고 select/update/delete 정책은 만들지 않습니다.
--   - 대시보드는 service_role 로 접속하므로 RLS와 무관하게 조회됩니다.
-- ---------------------------------------------------------------
alter table public.search_logs enable row level security;

-- RLS 정책과 별개로 테이블 권한도 있어야 insert 가 통과한다.
-- Supabase 가 기본 권한을 주긴 하지만, 이 파일만으로 재현되도록 명시한다.
grant insert on public.search_logs to anon, authenticated;

drop policy if exists "anyone can write a search log" on public.search_logs;
create policy "anyone can write a search log"
  on public.search_logs
  for insert
  to anon, authenticated
  with check (
    result_count >= 0
    and coalesce(array_length(result_ids, 1), 0) <= 200   -- 비정상적으로 큰 payload 차단
    and length(coalesce(session_id, '')) <= 64
  );

-- ---------------------------------------------------------------
-- 집계용 뷰 (대시보드에서 보기)
-- security_invoker = on : 뷰가 RLS를 우회하지 않도록 한다.
--   anon 은 search_logs 에 select 정책이 없으므로 뷰로도 못 읽습니다.
-- ---------------------------------------------------------------

-- 어떤 메뉴를 많이 찾는가
create or replace view public.stat_dish_searches
  with (security_invoker = on) as
select d as dish, count(*) as searches
from public.search_logs l,
     lateral jsonb_array_elements_text(l.filters -> 'dish') as d
where l.kind = 'search'
group by d
order by searches desc;

-- 어떤 식당이 결과에 자주 노출되는가
create or replace view public.stat_restaurant_exposure
  with (security_invoker = on) as
select r.id, r.name, r.campus, r.area, count(*) as shown
from public.search_logs l,
     lateral unnest(l.result_ids) as rid
join public.restaurants r on r.id = rid
where l.kind = 'search'
group by r.id, r.name, r.campus, r.area
order by shown desc;

-- 랜덤 추천에서 실제로 뽑힌 식당
create or replace view public.stat_random_picks
  with (security_invoker = on) as
select r.id, r.name, count(*) as picked
from public.search_logs l
join public.restaurants r on r.id = l.picked_id
where l.kind = 'pick'
group by r.id, r.name
order by picked desc;

-- 결과가 0건이었던 검색 = 수요는 있는데 데이터가 없는 조건
create or replace view public.stat_empty_searches
  with (security_invoker = on) as
select filters, count(*) as times, max(created_at) as last_seen
from public.search_logs
where kind = 'search' and result_count = 0
group by filters
order by times desc;

-- "원하는 식당을 찾았나" 응답률 — 서비스가 제 역할을 하는지 보는 지표
create or replace view public.stat_feedback
  with (security_invoker = on) as
select
  count(*)                          as answers,
  count(*) filter (where found)     as found_yes,
  count(*) filter (where not found) as found_no,
  round(100.0 * count(*) filter (where found) / nullif(count(*), 0), 1) as found_rate_pct
from public.search_logs
where kind = 'feedback';
-- 위 check 제약 덕분에 feedback 행의 found 는 항상 not null 이므로
-- answers = found_yes + found_no 가 성립한다.

-- 못 찾았다고 답했을 때 걸려 있던 조건 — 무엇이 부족한지 알려준다
create or replace view public.stat_feedback_missed
  with (security_invoker = on) as
select filters, result_count, count(*) as times, max(created_at) as last_seen
from public.search_logs
where kind = 'feedback' and found is false
group by filters, result_count
order by times desc;

revoke all on public.stat_dish_searches,
              public.stat_restaurant_exposure,
              public.stat_random_picks,
              public.stat_empty_searches,
              public.stat_feedback,
              public.stat_feedback_missed
  from anon, authenticated;
