create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  type text not null check (type in ('income', 'expense')),
  color text,
  icon text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists categories_user_id_idx on public.categories(user_id);
create index if not exists categories_user_id_type_idx on public.categories(user_id, type);

create unique index if not exists categories_user_id_id_uidx
on public.categories(user_id, id);

drop trigger if exists categories_set_updated_at on public.categories;
create trigger categories_set_updated_at
before update on public.categories
for each row
execute function public.set_updated_at();

alter table public.categories enable row level security;

drop policy if exists "Users can manage their own categories" on public.categories;
create policy "Users can manage their own categories" on public.categories
for all to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);
