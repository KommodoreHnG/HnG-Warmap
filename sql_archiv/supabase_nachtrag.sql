-- ############################################################
--  ARCHIV - NICHT MEHR AUSFUEHREN
-- ############################################################
--
--  Nachtrag zum ersten Aufbau. may_write mit 2 Zweigen.
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
    'supabase_nachtrag.sql';
end
$ARCHIVRIEGEL$;

-- ============================================================
--  Nachtrag zum bestehenden Projekt — im SQL-Editor ausfuehren.
--  Optional, nicht dringend.
--
--  Nur eine Regel wird schaerfer: die groben Staerkeschaetzungen
--  ("~1000 Infanterie") waren bisher fuer alle schreibbar, obwohl
--  die Seite sie als Eintrag ihres Verfassers behandelt und mit
--  einem Schloss anzeigt. Jetzt setzt das auch die Datenbank durch.
--
--  Fuer die beiden neuen Fenster ist NICHTS noetig: der Depotverlauf
--  reist im Eintrag depot:<player> mit und faellt damit unter die
--  Regel, die es schon gibt.
-- ============================================================
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
grant execute on function warmap_may_write(text, text) to anon;
