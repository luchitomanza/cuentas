-- Mis Cuentas Claras: grupos compartidos.
-- Ejecutar UNA vez en Supabase → SQL Editor → New query → Run, DESPUÉS de setup.sql.
-- Debe decir "Success. No rows returned".

-- 1) Tablas de grupos
create table if not exists public.grupos (
  id         uuid primary key default gen_random_uuid(),
  nombre     text not null check (char_length(nombre) between 1 and 40),
  creado_por uuid not null default auth.uid() references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.grupo_miembros (
  grupo_id uuid not null references public.grupos(id) on delete cascade,
  user_id  uuid not null references auth.users(id) on delete cascade,
  email    text not null,
  primary key (grupo_id, user_id)
);

-- 2) Cada registro puede pertenecer a un grupo (null = personal)
alter table public.registros add column if not exists grupo_id uuid references public.grupos(id) on delete cascade;
create index if not exists registros_grupo on public.registros (grupo_id, updated_at);

-- 3) Funciones auxiliares (evitan bucles de permisos)
create or replace function public.es_miembro(g uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.grupo_miembros m where m.grupo_id = g and m.user_id = auth.uid());
$$;

create or replace function public.es_creador(g uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.grupos x where x.id = g and x.creado_por = auth.uid());
$$;

-- 4) Seguridad de las tablas de grupos
alter table public.grupos enable row level security;
alter table public.grupo_miembros enable row level security;

drop policy if exists "ver mis grupos" on public.grupos;
create policy "ver mis grupos" on public.grupos for select to authenticated using (public.es_miembro(id));

drop policy if exists "ver miembros" on public.grupo_miembros;
create policy "ver miembros" on public.grupo_miembros for select to authenticated using (public.es_miembro(grupo_id));

revoke all on public.grupos from anon;
revoke all on public.grupo_miembros from anon;
grant select on public.grupos to authenticated;
grant select on public.grupo_miembros to authenticated;

-- 5) Seguridad de los registros: ver los propios y los de mis grupos;
--    crear solo en mis grupos; editar y borrar solo los que yo registré (ya existe).
drop policy if exists "ver lo propio" on public.registros;
create policy "ver lo propio y de mis grupos" on public.registros for select to authenticated
  using ((select auth.uid()) = user_id or (grupo_id is not null and public.es_miembro(grupo_id)));

drop policy if exists "crear lo propio" on public.registros;
create policy "crear lo propio" on public.registros for insert to authenticated
  with check ((select auth.uid()) = user_id and (grupo_id is null or public.es_miembro(grupo_id)));

-- 6) Funciones que usa la app
create or replace function public.crear_grupo(p_nombre text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare g uuid; mail text;
begin
  if auth.uid() is null then raise exception 'Inicia sesión primero'; end if;
  insert into public.grupos (nombre, creado_por) values (trim(p_nombre), auth.uid()) returning id into g;
  select email into mail from auth.users where id = auth.uid();
  insert into public.grupo_miembros (grupo_id, user_id, email) values (g, auth.uid(), lower(mail));
  return g;
end $$;

create or replace function public.agregar_miembro(p_grupo uuid, p_correo text) returns void
language plpgsql security definer set search_path = '' as $$
declare uid uuid; mail text := lower(trim(p_correo));
begin
  if not public.es_creador(p_grupo) then raise exception 'Solo quien creó el grupo puede invitar'; end if;
  select id into uid from auth.users where lower(email) = mail;
  if uid is null then raise exception 'Esa persona aún no tiene cuenta en la app'; end if;
  insert into public.grupo_miembros (grupo_id, user_id, email) values (p_grupo, uid, mail) on conflict do nothing;
end $$;

revoke all on function public.crear_grupo(text) from public, anon;
revoke all on function public.agregar_miembro(uuid, text) from public, anon;
grant execute on function public.crear_grupo(text) to authenticated;
grant execute on function public.agregar_miembro(uuid, text) to authenticated;
