-- ############################################################
--  ARCHIV - NICHT MEHR AUSFUEHREN
-- ############################################################
--
--  Der erste Aufbau. Legt Tabelle, Policies UND warmap_may_write neu an - mit 2 statt 11 Zweigen. Wuerde den kompletten Regelsatz zuruecksetzen.
--
--  Diese Datei ist ein ALTSTAND. Sie enthaelt "create or replace" und wuerde
--  beim Ausfuehren den heutigen Stand ueberschreiben - lautlos und in der
--  gefaehrlichen Richtung: was in ihr fehlt, faellt auf "else true" zurueck
--  und ist damit fuer jeden im Raum beschreibbar. Ein verlorener Zweig
--  verweigert nie, er ERLAUBT. Deshalb faellt so ein Schaden nicht auf.
--
--  DER GUELTIGE STAND STEHT IN:  supabase_stand_2026-08-21.sql
--
--  Der Riegel unten bricht ab, falls diese Datei doch einmal im SQL-Editor
--  landet. Wer sie wirklich braucht - etwa um nachzulesen, wie etwas frueher
--  aussah - liest sie, fuehrt sie aber nicht aus.
--
--  Aufgeraeumt am 22.08.2026. Siehe sql_archiv/LIESMICH.md
-- ############################################################
do $ARCHIVRIEGEL$
begin
  raise exception
    'ARCHIV: % darf nicht ausgefuehrt werden. Der gueltige Stand steht in supabase_stand_2026-08-21.sql.',
    'supabase_schema.sql';
end
$ARCHIVRIEGEL$;

-- ============================================================
--  War Map — Supabase schema
--  Paste into the Supabase SQL editor and press Run.
--  (Dashboard → SQL Editor → New query)
--
--  Access model: every player gets a personal invite code, which you
--  hand out on Discord. Nobody can read or write without one, and
--  assault teams can only be edited by the player who owns them.
--  All of that is enforced by the database, not by the page.
-- ============================================================

-- ---------- members ----------
-- code   = the secret you send someone on Discord (their identity)
-- player = public short id that appears inside data keys
create table if not exists warmap_member (
  room       text        not null,
  code       text        not null,
  player     text        not null,
  name       text        not null default '',
  approved   boolean     not null default false,
  is_admin   boolean     not null default false,
  created_at timestamptz not null default now(),
  last_seen  timestamptz,
  primary key (room, code),
  unique (room, player)
);

-- ---------- map data ----------
-- key is "owner:412", "units:412:a1b2c3", "note:412", "arrow:x9", "gone:x9"
create table if not exists warmap (
  room       text        not null,
  key        text        not null,
  value      jsonb       not null,
  updated_at timestamptz not null default now(),
  primary key (room, key)
);
create index if not exists warmap_room_time on warmap (room, updated_at desc);

-- ---------- who is calling ----------
-- PostgREST exposes request headers; the page sends its code in one.
create or replace function warmap_caller() returns text
language sql stable as $$
  select nullif(current_setting('request.headers', true)::json->>'x-warmap-code', '')
$$;

create or replace function warmap_member_of(r text) returns warmap_member
language sql stable security definer set search_path = public as $$
  select * from warmap_member
   where room = r and code = warmap_caller() and approved
   limit 1
$$;

create or replace function warmap_ok(r text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from warmap_member
                  where room = r and code = warmap_caller() and approved)
$$;

create or replace function warmap_player(r text) returns text
language sql stable security definer set search_path = public as $$
  select player from warmap_member
   where room = r and code = warmap_caller() and approved
$$;

-- What the page calls right after you press Connect. The code alone identifies
-- both the player and the room, so nobody has to be told a room name.
create or replace function warmap_whoami()
returns table (room text, player text, name text, is_admin boolean)
language sql volatile security definer set search_path = public as $$
  update warmap_member set last_seen = now()
   where code = warmap_caller() and approved
  returning room, player, name, is_admin
$$;

-- ---------- never let a stale edit win ----------
create or replace function warmap_keep_newest() returns trigger
language plpgsql as $$
begin
  if coalesce((new.value->>'t')::bigint, 0) < coalesce((old.value->>'t')::bigint, 0) then
    return old;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists warmap_keep_newest on warmap;
create trigger warmap_keep_newest before update on warmap
  for each row execute function warmap_keep_newest();

-- ---------- access rules ----------
alter table warmap enable row level security;
alter table warmap_member enable row level security;

-- Members: you may read your own row only. Nobody can hand out codes but you,
-- through the SQL editor. No insert/update/delete policy exists, so the anon
-- key cannot create members or approve itself.
drop policy if exists member_self on warmap_member;
create policy member_self on warmap_member
  for select using (code = warmap_caller());

-- Map data: approved members read everything in their room.
drop policy if exists warmap_read on warmap;
create policy warmap_read on warmap
  for select using (warmap_ok(room));

-- Writing: anyone approved may edit control, notes and arrows — that is the
-- shared picture. Assault teams are personal: the key must end in your own
-- player id, so you cannot touch someone else's.
-- Authored keys carry their writer, so only that player may change them:
--   units:<town>:<player>   depot:<player>        join:<arrow>:<player>
--   post:<id>:<player>      line:<id>:<player>    spot:<town>:<player>
--   area:<id>:<player>      est:<town>:<player>
-- depot:<player> also carries that player's growth history, so the same rule
-- keeps anyone from rewriting somebody else's past.
-- Deliberately shared, because the whole clan builds them up together:
--   roster:<key>  (who is out there)      edep:<key>  (what an enemy owns)
--   para:<town>   (para-blocks)           plus control, battles, stars, notes,
--   arrows and the clan settings — that is the common picture.
create or replace function warmap_may_write(r text, k text) returns boolean
language sql stable security definer set search_path = public as $$
  select case
    when k like 'depot:%' then split_part(k, ':', 2) = warmap_player(r)
    when k like 'units:%' or k like 'join:%' or k like 'post:%' or k like 'line:%'
      or k like 'spot:%'  or k like 'area:%' or k like 'est:%'
      then split_part(k, ':', 3) = warmap_player(r)
    else true
  end
$$;

drop policy if exists warmap_insert on warmap;
create policy warmap_insert on warmap for insert with check (
  warmap_ok(room)
  and length(key) <= 64
  and pg_column_size(value) < 20000
  and warmap_may_write(room, key)
);

drop policy if exists warmap_update on warmap;
create policy warmap_update on warmap for update
  using (warmap_ok(room) and warmap_may_write(room, key))
  with check (
    length(key) <= 64
    and pg_column_size(value) < 20000
    and warmap_may_write(room, key)
  );

-- No delete policy on purpose: removals are stored as {"v":null} tombstones,
-- so a deletion is not undone when someone syncs an older copy.

-- ---------- table privileges ----------
-- Policies only take effect once the role may touch the table at all.
-- Deliberately no DELETE anywhere, and no write access to the member list.
grant usage on schema public to anon;
grant select, insert, update on warmap to anon;
grant select on warmap_member to anon;
grant execute on function warmap_whoami() to anon;
grant execute on function warmap_caller() to anon;
grant execute on function warmap_ok(text) to anon;
grant execute on function warmap_player(text) to anon;
grant execute on function warmap_may_write(text, text) to anon;


-- ============================================================
--  Handing out access
-- ============================================================

-- Invite somebody. Returns the code to send them on Discord.
-- Example:  select * from warmap_invite('my-clan-room', 'Kommodore', true);
create or replace function warmap_invite(r text, player_name text, admin boolean default false)
returns table (code text, player text, name text)
language plpgsql security definer set search_path = public as $$
declare c text; p text;
begin
  -- gen_random_uuid() steckt seit PostgreSQL 13 im Kern. gen_random_bytes()
  -- kaeme aus pgcrypto und liegt in Supabase im Schema "extensions" - mit
  -- search_path = public waere es hier ohnehin unsichtbar.
  c := substr(replace(gen_random_uuid()::text, '-', ''), 1, 10)
    || substr(replace(gen_random_uuid()::text, '-', ''), 1, 6);
  p := substr(md5(c || r), 1, 6);
  insert into warmap_member (room, code, player, name, approved, is_admin)
       values (r, c, p, player_name, true, admin);
  return query select c, p, player_name;
end;
$$;
revoke execute on function warmap_invite(text, text, boolean) from anon, authenticated;

-- Everyday admin, run from the SQL editor:
--   select room, player, name, approved, is_admin, last_seen from warmap_member order by name;
--   update warmap_member set approved = false where room = '…' and name = '…';   -- lock somebody out
--   delete from warmap_member where room = '…' and name = '…';                   -- remove them
--   delete from warmap where room = '…' and key like 'units:%:PLAYERID';          -- clear their teams

-- Optional housekeeping:
--   delete from warmap where updated_at < now() - interval '90 days';
