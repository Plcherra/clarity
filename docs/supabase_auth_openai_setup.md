# Supabase Auth And OpenAI Edge Function Setup

## Flutter Config

`pubspec.yaml` includes:

```yaml
dependencies:
  supabase_flutter: ^2.12.4
```

Flutter `.env` must contain only public Supabase client config:

```dotenv
SUPABASE_URL=https://your-project-ref.supabase.co
SUPABASE_ANON_KEY=your-public-anon-key
```

Never put the OpenAI secret in Flutter `.env`, committed files, or client assets.

## SQL Schema And RLS

Run this in the Supabase SQL editor:

```sql
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  full_name text not null default '',
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

drop policy if exists "Users can read their own profile" on public.profiles;
create policy "Users can read their own profile"
on public.profiles
for select
to authenticated
using ((select auth.uid()) = id);

drop policy if exists "Users can insert their own profile" on public.profiles;
create policy "Users can insert their own profile"
on public.profiles
for insert
to authenticated
with check ((select auth.uid()) = id);

drop policy if exists "Users can update their own profile" on public.profiles;
create policy "Users can update their own profile"
on public.profiles
for update
to authenticated
using ((select auth.uid()) = id)
with check ((select auth.uid()) = id);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
before update on public.profiles
for each row
execute function public.set_updated_at();

create or replace function public.handle_new_user_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, full_name)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data ->> 'full_name', '')
  )
  on conflict (id) do update
  set
    email = excluded.email,
    full_name = coalesce(nullif(excluded.full_name, ''), public.profiles.full_name),
    updated_at = now();

  return new;
end;
$$;

drop trigger if exists on_auth_user_created_profile on auth.users;
create trigger on_auth_user_created_profile
after insert on auth.users
for each row
execute function public.handle_new_user_profile();
```

## Edge Function

The function lives at `supabase/functions/call-openai/index.ts`.

Deploy it:

```sh
supabase functions deploy call-openai
```

Set the server-side OpenAI secret:

```sh
supabase secrets set OPENAI_API_KEY=your-real-openai-key
```

Run locally:

```sh
supabase functions serve call-openai --env-file supabase/functions/.env
```

For local Edge Function testing only, `supabase/functions/.env` may contain:

```dotenv
OPENAI_API_KEY=your-real-openai-key
```

Do not commit that file.
