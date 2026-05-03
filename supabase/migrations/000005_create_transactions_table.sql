create table if not exists public.transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  account_id uuid not null,
  category_id uuid,
  amount numeric(12,2) not null,
  type text not null check (type in ('income', 'expense')),
  description text,
  date date not null,
  merchant text,
  imported_from_csv boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint transactions_account_user_fk
    foreign key (user_id, account_id)
    references public.accounts(user_id, id)
    on delete cascade,
  constraint transactions_category_user_fk
    foreign key (user_id, category_id)
    references public.categories(user_id, id)
    on delete set null (category_id)
);

create index if not exists transactions_user_id_idx on public.transactions(user_id);
create index if not exists transactions_account_id_idx on public.transactions(account_id);
create index if not exists transactions_category_id_idx on public.transactions(category_id);
create index if not exists transactions_user_id_date_idx on public.transactions(user_id, date desc);

drop trigger if exists transactions_set_updated_at on public.transactions;
create trigger transactions_set_updated_at
before update on public.transactions
for each row
execute function public.set_updated_at();

alter table public.transactions enable row level security;

drop policy if exists "Users can manage their own transactions" on public.transactions;
create policy "Users can manage their own transactions" on public.transactions
for all to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);
