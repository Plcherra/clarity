create table if not exists public.budgets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  amount numeric(12,2) not null,
  period text not null check (period in ('monthly', 'weekly', 'custom', 'yearly')),
  start_date date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists budgets_user_id_idx on public.budgets(user_id);
create index if not exists budgets_user_id_period_idx on public.budgets(user_id, period);
create index if not exists budgets_user_id_period_start_date_idx
on public.budgets(user_id, period, start_date);

drop trigger if exists budgets_set_updated_at on public.budgets;
create trigger budgets_set_updated_at
before update on public.budgets
for each row
execute function public.set_updated_at();

alter table public.budgets enable row level security;

drop policy if exists "Users can manage their own budgets" on public.budgets;
create policy "Users can manage their own budgets" on public.budgets
for all to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);
