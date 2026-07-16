-- =====================================================================
-- Valyn Advisory — Auto Nejma Pricing Tracker
-- Supabase / Postgres schema + Row-Level Security + seed
-- Run this once in Supabase Studio → SQL Editor.
-- =====================================================================

-- ---------- Extensions ----------
create extension if not exists "pgcrypto";

-- ---------- Enums ----------
do $$ begin
  create type user_role as enum ('admin','client');
exception when duplicate_object then null; end $$;

-- ---------- profiles (one row per auth user) ----------
create table if not exists public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  name       text not null default '',
  org        text not null default 'Auto Nejma',
  role       user_role not null default 'client',
  email      text,
  active     boolean not null default true,
  -- capability map, e.g. {"dashboard":true,"benchmark":false,...}
  rights     jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- ---------- vehicles (catalog of tracked / benchmark finitions) ----------
create table if not exists public.vehicles (
  id         uuid primary key default gen_random_uuid(),
  org        text not null default 'Auto Nejma',      -- which client this belongs to
  marque     text not null,
  modele     text not null,
  motor      text default '',
  finition   text default '',
  segment    text default 'Divers',
  type       text default 'Thermique',                -- Thermique / Électrique / Hybride rechargeable
  fi         integer default 7105,                    -- frais d'immatriculation
  catalogue  numeric,
  vrole      text default 'client',                   -- 'client' (tracked) | 'catalog' (reference)
  comment    text default '',
  status_override text,
  created_at timestamptz not null default now(),
  unique (org, marque, modele, finition)
);

-- ---------- monthly_data (one row per vehicle per month) ----------
create table if not exists public.monthly_data (
  id         uuid primary key default gen_random_uuid(),
  vehicle_id uuid not null references public.vehicles(id) on delete cascade,
  period     date not null,                           -- first day of month, e.g. 2026-06-01
  showroom   numeric,                                 -- prix showroom TTC
  remise     numeric,                                 -- optional stored discount (0..1)
  cem_obs    numeric,                                 -- observed CEM (used to back-solve remise)
  created_at timestamptz not null default now(),
  unique (vehicle_id, period)
);

-- ---------- broadcasts (alerts / messages admin -> client) ----------
create table if not exists public.broadcasts (
  id         uuid primary key default gen_random_uuid(),
  org        text not null default 'Auto Nejma',      -- target organisation
  title      text not null,
  body       text not null,
  priority   text not null default 'info',            -- info | moyenne | élevée
  from_name  text not null default 'Valyn Advisory',
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

-- ---------- reads (which user read which broadcast) ----------
create table if not exists public.reads (
  user_id      uuid not null references auth.users(id) on delete cascade,
  broadcast_id uuid not null references public.broadcasts(id) on delete cascade,
  read_at      timestamptz not null default now(),
  primary key (user_id, broadcast_id)
);

-- =====================================================================
-- Helper: is the current user an admin?
-- SECURITY DEFINER so it can read profiles without recursive RLS.
-- =====================================================================
create or replace function public.is_admin()
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'admin' and p.active
  );
$$;

create or replace function public.my_org()
returns text
language sql stable security definer set search_path = public as $$
  select org from public.profiles where id = auth.uid();
$$;

-- =====================================================================
-- Auto-create a profile row when a new auth user signs up.
-- New users start as client, read-only, inactive until admin enables.
-- =====================================================================
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, name, org, role, email, active, rights)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'name', split_part(new.email,'@',1)),
    coalesce(new.raw_user_meta_data->>'org', 'Auto Nejma'),
    'client',
    new.email,
    false,
    '{"dashboard":true,"tracked":true,"reports":true}'::jsonb
  )
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- =====================================================================
-- Row-Level Security
-- =====================================================================
alter table public.profiles     enable row level security;
alter table public.vehicles     enable row level security;
alter table public.monthly_data enable row level security;
alter table public.broadcasts   enable row level security;
alter table public.reads        enable row level security;

-- profiles: user reads own row; admin reads/writes all; user may update own basic fields.
drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles for select
  using ( id = auth.uid() or public.is_admin() );

drop policy if exists profiles_admin_write on public.profiles;
create policy profiles_admin_write on public.profiles for all
  using ( public.is_admin() ) with check ( public.is_admin() );

-- vehicles: admin full; client reads only its org.
drop policy if exists vehicles_admin on public.vehicles;
create policy vehicles_admin on public.vehicles for all
  using ( public.is_admin() ) with check ( public.is_admin() );

drop policy if exists vehicles_client_read on public.vehicles;
create policy vehicles_client_read on public.vehicles for select
  using ( org = public.my_org() );

-- monthly_data: admin full; client reads rows for vehicles in its org.
drop policy if exists monthly_admin on public.monthly_data;
create policy monthly_admin on public.monthly_data for all
  using ( public.is_admin() ) with check ( public.is_admin() );

drop policy if exists monthly_client_read on public.monthly_data;
create policy monthly_client_read on public.monthly_data for select
  using ( exists (select 1 from public.vehicles v where v.id = vehicle_id and v.org = public.my_org()) );

-- broadcasts: admin full; client reads only its org.
drop policy if exists broadcasts_admin on public.broadcasts;
create policy broadcasts_admin on public.broadcasts for all
  using ( public.is_admin() ) with check ( public.is_admin() );

drop policy if exists broadcasts_client_read on public.broadcasts;
create policy broadcasts_client_read on public.broadcasts for select
  using ( org = public.my_org() );

-- reads: each user manages only its own read receipts.
drop policy if exists reads_own on public.reads;
create policy reads_own on public.reads for all
  using ( user_id = auth.uid() ) with check ( user_id = auth.uid() );

-- =====================================================================
-- Storage buckets (proofs + monthly imports). Run, then set policies below.
-- =====================================================================
insert into storage.buckets (id, name, public) values ('proofs','proofs', false)
  on conflict (id) do nothing;
insert into storage.buckets (id, name, public) values ('imports','imports', false)
  on conflict (id) do nothing;

drop policy if exists proofs_admin_all on storage.objects;
create policy proofs_admin_all on storage.objects for all
  using ( bucket_id in ('proofs','imports') and public.is_admin() )
  with check ( bucket_id in ('proofs','imports') and public.is_admin() );

drop policy if exists proofs_client_read on storage.objects;
create policy proofs_client_read on storage.objects for select
  using ( bucket_id = 'proofs' );  -- tighten by org path prefix if needed

-- =====================================================================
-- SEED DATA (real values from Document Excel Auto Najma.xlsx)
-- Profiles are NOT seeded here (they need auth.users). See README step 4.
-- =====================================================================
-- Vehicles + June/May 2026 monthly points. Safe to re-run.
do $$
declare vid uuid;
begin
  -- helper block inserts a vehicle then its monthly rows
  -- A3 EMOTION
  insert into public.vehicles(org,marque,modele,motor,finition,segment,type,fi,catalogue,vrole,comment)
  values('Auto Nejma','AUDI','A3 Sportback','2.0 TDI','EMOTION','Compactes Hatchback','Thermique',7105,438000,'client','Très bonne remise sur la 1ère finition A3.')
  on conflict (org,marque,modele,finition) do update set catalogue=excluded.catalogue returning id into vid;
  insert into public.monthly_data(vehicle_id,period,showroom,remise) values
    (vid,'2025-12-01',440000,0.13432954545454562),(vid,'2026-01-01',438000,0.08339269406392688),
    (vid,'2026-02-01',438000,0.08339269406392688),(vid,'2026-03-01',438000,0.08339269406392688),
    (vid,'2026-04-01',438000,0.08339269406392688),(vid,'2026-05-01',438000,0.08339269406392688)
    on conflict (vehicle_id,period) do nothing;
  insert into public.monthly_data(vehicle_id,period,showroom,remise,cem_obs) values
    (vid,'2026-06-01',438000,0.08339269406392688,410000) on conflict (vehicle_id,period) do nothing;

  -- A3 S-LINE
  insert into public.vehicles(org,marque,modele,motor,finition,segment,type,fi,catalogue,vrole,comment)
  values('Auto Nejma','AUDI','A3 Sportback','2.0 TDI','S-LINE','Compactes Hatchback','Thermique',7105,543000,'client','Stock limité. Remise majoritairement fiscale.')
  on conflict (org,marque,modele,finition) do update set catalogue=excluded.catalogue returning id into vid;
  insert into public.monthly_data(vehicle_id,period,showroom,remise) values
    (vid,'2026-02-01',543000,0.11883241252302017),(vid,'2026-03-01',543000,0.11883241252302017),
    (vid,'2026-04-01',543000,0.11883241252302017),(vid,'2026-05-01',543000,0.11883241252302017)
    on conflict (vehicle_id,period) do nothing;
  insert into public.monthly_data(vehicle_id,period,showroom,remise,cem_obs) values
    (vid,'2026-06-01',543000,0.1169907918968692,488000) on conflict (vehicle_id,period) do nothing;

  -- A3 BLACK EDITION (new June, solve remise from CEM)
  insert into public.vehicles(org,marque,modele,motor,finition,segment,type,fi,catalogue,vrole,comment,status_override)
  values('Auto Nejma','AUDI','A3 Sportback','2.0 TDI','BLACK EDITION','Compactes Hatchback','Thermique',7105,475000,'client','Prix promotionnel. Nouvelle finition juin.','Nouveau')
  on conflict (org,marque,modele,finition) do update set catalogue=excluded.catalogue returning id into vid;
  insert into public.monthly_data(vehicle_id,period,showroom,cem_obs) values
    (vid,'2026-06-01',475000,439000) on conflict (vehicle_id,period) do nothing;

  -- A5 S EDITION
  insert into public.vehicles(org,marque,modele,motor,finition,segment,type,fi,catalogue,vrole,comment)
  values('Auto Nejma','AUDI','A5 Berline','2.0 TDI','S EDITION','Executive Compactes','Thermique',7105,756000,'client','Prix promotionnel jusqu''à épuisement.')
  on conflict (org,marque,modele,finition) do update set catalogue=excluded.catalogue returning id into vid;
  insert into public.monthly_data(vehicle_id,period,showroom,remise) values
    (vid,'2025-12-01',700000,0.10567167919799493),(vid,'2026-01-01',756000,0.07221718316956406),
    (vid,'2026-02-01',756000,0.07599647266313929),(vid,'2026-03-01',756000,0.15536155202821866),
    (vid,'2026-04-01',746000,0.14276267075194682),(vid,'2026-05-01',746000,0.14276267075194682)
    on conflict (vehicle_id,period) do nothing;
  insert into public.monthly_data(vehicle_id,period,showroom,remise,cem_obs) values
    (vid,'2026-06-01',746000,0.14276267075194682,680000) on conflict (vehicle_id,period) do nothing;

  -- A5 BUSINESS (new June)
  insert into public.vehicles(org,marque,modele,motor,finition,segment,type,fi,catalogue,vrole,comment,status_override)
  values('Auto Nejma','AUDI','A5 Berline','2.0 TDI','BUSINESS','Executive Compactes','Thermique',7105,630000,'client','Offre promo. Nouvelle finition juin.','Nouveau')
  on conflict (org,marque,modele,finition) do update set catalogue=excluded.catalogue returning id into vid;
  insert into public.monthly_data(vehicle_id,period,showroom,cem_obs) values
    (vid,'2026-06-01',630000,598000) on conflict (vehicle_id,period) do nothing;

  -- A6 NOUVELLE 2026 (out of scope June)
  insert into public.vehicles(org,marque,modele,motor,finition,segment,type,fi,catalogue,vrole,comment,status_override)
  values('Auto Nejma','AUDI','A6','2.0 TDI','NOUVELLE 2026','Executive','Thermique',7105,690000,'client','Indisponible juin — arrivage septembre.','Hors scope')
  on conflict (org,marque,modele,finition) do update set catalogue=excluded.catalogue returning id into vid;
  insert into public.monthly_data(vehicle_id,period,showroom,remise) values
    (vid,'2025-12-01',690000,0.09131197559115178),(vid,'2026-01-01',690000,0.09251345755693582),
    (vid,'2026-02-01',690000,0.08975293305728078),(vid,'2026-03-01',690000,0.09251345755693584),
    (vid,'2026-04-01',690000,0.09251345755693584),(vid,'2026-05-01',690000,0.09251345755693584)
    on conflict (vehicle_id,period) do nothing;
end $$;
