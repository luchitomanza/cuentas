-- Mis Cuentas Claras: base de datos.
-- Pega todo esto en Supabase → SQL Editor → New query → Run (una sola vez).

create table if not exists public.registros (
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  id         text not null,
  data       jsonb not null default '{}'::jsonb,
  deleted    boolean not null default false,
  updated_at timestamptz not null default clock_timestamp(),
  primary key (user_id, id)
);
create index if not exists registros_user_updated on public.registros (user_id, updated_at);

-- Cada persona solo puede ver y cambiar sus propios registros.
alter table public.registros enable row level security;

drop policy if exists "ver lo propio" on public.registros;
drop policy if exists "crear lo propio" on public.registros;
drop policy if exists "editar lo propio" on public.registros;
drop policy if exists "borrar lo propio" on public.registros;
create policy "ver lo propio"    on public.registros for select to authenticated using ((select auth.uid()) = user_id);
create policy "crear lo propio"  on public.registros for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "editar lo propio" on public.registros for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "borrar lo propio" on public.registros for delete to authenticated using ((select auth.uid()) = user_id);

revoke all on public.registros from anon;
grant select, insert, update, delete on public.registros to authenticated;

-- Marca la hora exacta de cada cambio (sirve para sincronizar los equipos).
create or replace function public.registros_touch() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at := clock_timestamp();
  return new;
end $$;
drop trigger if exists registros_touch on public.registros;
create trigger registros_touch before insert or update on public.registros
for each row execute function public.registros_touch();
