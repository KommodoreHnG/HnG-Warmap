-- ############################################################
--  ARCHIV - NICHT MEHR AUSFUEHREN
-- ############################################################
--
--  Legte warmap_recode an - eine Funktion, die live GAR NICHT existiert. Wurde also nie eingespielt oder wieder entfernt.
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
    'supabase_neuercode.sql';
end
$ARCHIVRIEGEL$;

-- ============================================================
--  Neuen Code fuer ein BESTEHENDES Mitglied
--  Einmal im SQL-Editor von Supabase ausfuehren.
-- ============================================================
--
--  Warum es diese Funktion braucht:
--  Die Spielerkennung wird beim Einladen aus dem Code abgeleitet
--  (player = md5(code || room)). Wer sein Passwort vergisst und ueber
--  "Einladen" einen neuen Code bekaeme, bekaeme damit auch eine neue
--  Kennung - und saemtliche Daten, die an der alten haengen (Depot,
--  aufgestellte Truppen, Verlauf), waeren verwaist.
--
--  warmap_recode tauscht deshalb NUR den Code aus. Die Kennung, der Name,
--  die Rolle und alles Geschriebene bleiben.
--
--  Ablauf beim vergessenen Passwort:
--    1. Das Mitglied meldet sich beim Clanleiter (Discord).
--    2. Der erzeugt hier einen neuen Code und schickt ihn als
--       Direktnachricht.
--    3. Das Mitglied loest ihn ein und vergibt ein neues Passwort.
--  Nur zwischen 2 und 3 ist der Zugang ungeschuetzt - deshalb kurz halten.

create or replace function warmap_recode(target_player text)
returns table (code text, player text, name text)
language plpgsql security definer set search_path = public as $$
declare
  ich warmap_member;
  ziel warmap_member;
  c text; versuch int := 0;
begin
  ich := warmap_ich();
  if ich.code is null or not ich.is_admin then
    raise exception 'Nur Verwalter duerfen das';
  end if;
  select * into ziel from warmap_member
   where room = ich.room and player = target_player;
  if not found then
    raise exception 'Kein solches Mitglied';
  end if;

  -- Neuer Code, bis er im Raum eindeutig ist. Die Kennung bleibt, wie sie ist:
  -- daran haengen die Daten.
  loop
    versuch := versuch + 1;
    c := substr(replace(gen_random_uuid()::text, '-', ''), 1, 10)
      || substr(replace(gen_random_uuid()::text, '-', ''), 1, 6);
    exit when not exists (select 1 from warmap_member m where m.room = ich.room and m.code = c);
    if versuch > 8 then
      raise exception 'Konnte keinen freien Code finden';
    end if;
  end loop;

  update warmap_member m set code = c
   where m.room = ich.room and m.player = target_player;

  return query select c, ziel.player, ziel.name;
end
$$;
revoke execute on function warmap_recode(text) from public;
grant  execute on function warmap_recode(text) to anon, authenticated;
