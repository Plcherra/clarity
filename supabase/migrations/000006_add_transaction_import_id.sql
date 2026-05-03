alter table public.transactions
add column if not exists import_id text;

create index if not exists transactions_user_id_import_id_idx
on public.transactions(user_id, import_id)
where import_id is not null;
