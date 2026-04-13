-- ================================================================
-- SCHEMA SUPABASE — Polycopié LLG
-- Coller ce code dans : Supabase > SQL Editor > New Query > Run
-- ================================================================

-- Table des profils utilisateurs (liée à auth.users de Supabase)
create table public.profiles (
  id uuid references auth.users(id) on delete cascade primary key,
  username text unique not null,
  created_at timestamptz default now()
);

-- Table des exercices cochés + notes
create table public.exercises (
  id bigserial primary key,
  user_id uuid references public.profiles(id) on delete cascade not null,
  exercise_num integer not null check (exercise_num between 1 and 561),
  done boolean default false,
  notes text default '',
  updated_at timestamptz default now(),
  unique(user_id, exercise_num)
);

-- Table du streak (jours d'activité)
create table public.activity_days (
  id bigserial primary key,
  user_id uuid references public.profiles(id) on delete cascade not null,
  day date not null,
  unique(user_id, day)
);

-- ── INDEX pour les performances ──
create index on public.exercises(user_id);
create index on public.activity_days(user_id);

-- ── ROW LEVEL SECURITY ──
-- Chaque utilisateur ne peut lire/écrire que ses propres données
-- sauf les profils et stats qui sont publics (pour le classement)

alter table public.profiles enable row level security;
alter table public.exercises enable row level security;
alter table public.activity_days enable row level security;

-- Profils : lecture publique, écriture seulement pour soi
create policy "Profils visibles par tous" on public.profiles
  for select using (true);

create policy "Créer son propre profil" on public.profiles
  for insert with check (auth.uid() = id);

create policy "Modifier son propre profil" on public.profiles
  for update using (auth.uid() = id);

-- Exercices : lecture publique (pour classement), écriture seulement pour soi
create policy "Exercices visibles par tous" on public.exercises
  for select using (true);

create policy "Gérer ses propres exercices" on public.exercises
  for all using (auth.uid() = user_id);

-- Activité : lecture publique, écriture seulement pour soi
create policy "Activité visible par tous" on public.activity_days
  for select using (true);

create policy "Gérer sa propre activité" on public.activity_days
  for all using (auth.uid() = user_id);

-- ── TRIGGER : créer le profil automatiquement à l'inscription ──
-- (le username sera mis à jour depuis le front)
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, username)
  values (new.id, split_part(new.email, '@', 1));
  return new;
end;
$$ language plpgsql security definer;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ── VUE pour les stats du classement ──
create or replace view public.leaderboard as
select
  p.id,
  p.username,
  count(e.id) filter (where e.done = true) as done_count,
  count(distinct ad.day) as total_days,
  p.created_at
from public.profiles p
left join public.exercises e on e.user_id = p.id
left join public.activity_days ad on ad.user_id = p.id
group by p.id, p.username, p.created_at
order by done_count desc;

-- Accès public à la vue
grant select on public.leaderboard to anon, authenticated;
