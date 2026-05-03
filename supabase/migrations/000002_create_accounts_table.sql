create table if not exists public.accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  type text not null,
  balance numeric(12,2) not null default 0,
  currency text not null default 'USD',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists accounts_user_id_idx on public.accounts(user_id);
create index if not exists accounts_user_id_is_active_idx on public.accounts(user_id, is_active);

create unique index if not exists accounts_user_id_id_uidx
on public.accounts(user_id, id);

drop trigger if exists accounts_set_updated_at on public.accounts;
create trigger accounts_set_updated_at
before update on public.accounts
for each row
execute function public.set_updated_at();

alter table public.accounts enable row level security;

drop policy if exists "Users can manage their own accounts" on public.accounts;
create policy "Users can manage their own accounts" on public.accounts
for all to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);
