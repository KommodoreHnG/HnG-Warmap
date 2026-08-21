-- ############################################################
--  ARCHIV - NICHT MEHR AUSFUEHREN
-- ############################################################
--
--  Legte die Mitgliederverwaltung an (warmap_ich, invite_me, members, member_set, member_drop). Diese Funktionen laufen heute live; die Datei koennte einen aelteren Stand tragen.
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
    'supabase_mitglieder.sql';
end
$ARCHIVRIEGEL$;

-- ============================================================
--  Mitgliederverwaltung aus der Karte heraus
--  Im Supabase-SQL-Editor einfuegen und ausfuehren. Einmalig.
--
--  Bisher konntest du Codes nur hier im SQL-Editor vergeben. Danach geht es
--  in der Karte selbst, ueber den Knopf "Members" - der erscheint nur bei
--  Verwaltern.
--
--  Der entscheidende Punkt: der Raum kommt IMMER aus der Zeile des Aufrufers,
--  nie aus einem Parameter. Ein Verwalter kann damit ausschliesslich in den
--  eigenen Raum einladen und in keinen fremden.
-- ============================================================

-- ---------- Wer bin ich, und darf ich verwalten? ----------
create or replace function warmap_ich() returns warmap_member
language sql stable security definer set search_path = public as $$
  select * from warmap_member
   where code = warmap_caller() and approved
   limit 1
$$;

-- ---------- Einladen ----------
-- Gibt den Code zurueck, den du der Person auf Discord schickst.
create or replace function warmap_invite_me(player_name text,
                                            make_admin boolean default false)
returns table (code text, player text, name text)
language plpgsql security definer set search_path = public as $$
declare
  ich warmap_member;
  c text; p text; nm text; versuch int := 0;
begin
  ich := warmap_ich();
  if ich.code is null then
    raise exception 'Kein gueltiger Code';
  end if;
  if not ich.is_admin then
    raise exception 'Nur Verwalter duerfen einladen';
  end if;
  nm := nullif(btrim(player_name), '');
  if nm is null then
    raise exception 'Name fehlt';
  end if;
  if length(nm) > 40 then
    raise exception 'Name zu lang';
  end if;

  loop
    versuch := versuch + 1;
    c := substr(replace(gen_random_uuid()::text, '-', ''), 1, 10)
      || substr(replace(gen_random_uuid()::text, '-', ''), 1, 6);
    p := substr(md5(c || ich.room), 1, 6);
    begin
      insert into warmap_member (room, code, player, name, approved, is_admin)
           values (ich.room, c, p, nm, true, coalesce(make_admin, false));
      exit;
    exception when unique_violation then
      if versuch > 5 then
        raise exception 'Konnte keine freie Kennung finden';
      end if;
    end;
  end loop;

  return query select c, p, nm;
end
$$;

-- ---------- Mitglieder auflisten ----------
-- Verwalter sehen die Codes, alle anderen nur die Namen. Das ist Absicht:
-- ein Code ist der Schluessel zum Raum.
create or replace function warmap_members()
returns table (code text, player text, name text, approved boolean,
               is_admin boolean, created_at timestamptz, last_seen timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare ich warmap_member;
begin
  ich := warmap_ich();
  if ich.code is null then
    raise exception 'Kein gueltiger Code';
  end if;
  return query
    select case when ich.is_admin then w.code else null end,
           w.player, w.name, w.approved, w.is_admin, w.created_at, w.last_seen
      from warmap_member w
     where w.room = ich.room
     order by w.is_admin desc, lower(w.name);
end
$$;

-- ---------- Sperren, entsperren, zum Verwalter machen ----------
-- null heisst "so lassen". Auf sich selbst wirkt nur das Umbenennen.
create or replace function warmap_member_set(target_player text,
                                             set_approved boolean default null,
                                             set_admin boolean default null,
                                             set_name text default null)
returns boolean
language plpgsql security definer set search_path = public as $$
declare ich warmap_member; anzahl int;
begin
  ich := warmap_ich();
  if ich.code is null or not ich.is_admin then
    raise exception 'Nur Verwalter duerfen das';
  end if;
  if target_player = ich.player and (set_approved is not null or set_admin is not null) then
    raise exception 'Sich selbst kann man nicht sperren oder degradieren';
  end if;
  -- Der letzte Verwalter bleibt Verwalter, sonst sperrt sich der Raum aus.
  if set_admin is false then
    select count(*) into anzahl from warmap_member
     where room = ich.room and is_admin and approved;
    if anzahl <= 1 then
      raise exception 'Der letzte Verwalter kann nicht degradiert werden';
    end if;
  end if;
  update warmap_member set
      approved = coalesce(set_approved, approved),
      is_admin = coalesce(set_admin, is_admin),
      name     = coalesce(nullif(btrim(set_name), ''), name)
   where room = ich.room and player = target_player;
  return found;
end
$$;

-- ---------- Entfernen ----------
-- Loescht die Zeile. Was die Person bereits geschrieben hat, bleibt stehen -
-- ihr Code wirkt aber sofort nicht mehr.
create or replace function warmap_member_drop(target_player text)
returns boolean
language plpgsql security definer set search_path = public as $$
declare ich warmap_member;
begin
  ich := warmap_ich();
  if ich.code is null or not ich.is_admin then
    raise exception 'Nur Verwalter duerfen das';
  end if;
  if target_player = ich.player then
    raise exception 'Sich selbst kann man nicht entfernen';
  end if;
  delete from warmap_member where room = ich.room and player = target_player;
  return found;
end
$$;

-- ---------- Freigaben ----------
-- Die Pruefung steckt jeweils IN der Funktion; ohne gueltigen Verwaltercode
-- kommt eine Ausnahme zurueck, kein Datensatz.
grant execute on function warmap_ich()              to anon;
grant execute on function warmap_invite_me(text, boolean)                     to anon;
grant execute on function warmap_members()                                    to anon;
grant execute on function warmap_member_set(text, boolean, boolean, text)     to anon;
grant execute on function warmap_member_drop(text)                            to anon;

-- Die alte Funktion bleibt fuer den Notfall im SQL-Editor, aber weiterhin
-- gesperrt fuer die Webseite:
--   select * from warmap_invite('raumname', 'Spielername', true);
