create or replace function public.normalize_category_name(input text)
returns text
language sql
immutable
as $$
  select nullif(
    regexp_replace(
      regexp_replace(
        replace(lower(trim(coalesce(input, ''))), '&', ' and '),
        '[^a-z0-9]+',
        ' ',
        'g'
      ),
      '[[:space:]]+',
      ' ',
      'g'
    ),
    ''
  );
$$;

alter table public.categories
add column if not exists normalized_name text;

update public.categories
set normalized_name = public.normalize_category_name(name)
where normalized_name is null or trim(normalized_name) = '';

alter table public.categories
alter column normalized_name set not null;

alter table public.categories
drop constraint if exists categories_normalized_name_not_empty;

alter table public.categories
add constraint categories_normalized_name_not_empty
check (trim(normalized_name) <> '');

create unique index if not exists categories_user_id_normalized_name_uidx
on public.categories(user_id, normalized_name);

create or replace function public.set_category_normalized_name()
returns trigger
language plpgsql
as $$
begin
  new.normalized_name := public.normalize_category_name(new.name);
  if new.normalized_name is null or trim(new.normalized_name) = '' then
    raise exception 'Category name cannot be normalized';
  end if;
  return new;
end;
$$;

drop trigger if exists categories_set_normalized_name on public.categories;
create trigger categories_set_normalized_name
before insert or update of name on public.categories
for each row
execute function public.set_category_normalized_name();
