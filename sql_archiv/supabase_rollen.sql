-- ############################################################
--  ARCHIV - NICHT MEHR AUSFUEHREN
-- ############################################################
--
--  Fuehrte die Rollen ein. may_write mit 4 Zweigen.
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
    'supabase_rollen.sql';
end
$ARCHIVRIEGEL$;

-- ============================================================
--  Clanleiter, Raenge, privates Notizbuch
--  Einmal im SQL-Editor von Supabase ausfuehren.
--  Aendert keine Daten, nur Regeln. Gefahrlos mehrfach ausfuehrbar.
-- ============================================================
--
--  Was dazukommt
--  -------------
--  1. Zwei Aemter statt einem.
--     Bisher war "Verwalter" alles: Codes ausgeben UND befehlen. Das
--     vermischt zwei Dinge, die nichts miteinander zu tun haben. Wer den
--     Server bezahlt, ist nicht deshalb der, der sagt, wo angegriffen wird.
--
--     Verwalter  (is_admin)     - Codes, Mitgliederliste, Beschriftungen.
--     Clanleiter (meta:leader)  - Fraktion, Befehle, Raenge.
--
--  2. Was nur der Leiter schreiben darf, sagt ab jetzt die Datenbank:
--       meta:leader     wer fuehrt          (der Verwalter darf das auch)
--       meta:rollen     welche Raenge es gibt
--       meta:rang       wer welchen hat
--       meta:standrang  was gilt, wenn keiner zugeteilt ist
--       meta:clanf      welche Seite der Clan spielt
--       meta:epoch      wann ein neuer Krieg beginnt
--
--  3. Zwei neue Toepfe, die nur ihrem Verfasser gehoeren:
--       priv:<player>   das private Notizbuch (verschluesselt, siehe unten)
--       wish:<player>   was jemand im naechsten Krieg machen moechte
--       first:<x>:<player>  wer etwas als Erster aufgeklaert hat
--       sweep:<player>  wann er welchen Kartensektor zuletzt abgesucht hat
--
--     first: ist Absicht so gebaut - jeder Anspruch eine eigene Zeile, die
--     nur ihrem Verfasser gehoert. Niemand kann den Fund eines anderen
--     ueberschreiben; ausgewertet gewinnt der fruehste Zeitstempel.
--
--  Was diese Datei bewusst NICHT durchsetzt
--  ----------------------------------------
--  Befehle geben, Vorschlaege bestaetigen, fremde Marken raeumen, Hilfe
--  rufen: das haengt am Rang, und der steht als JSON in meta:rollen. Die
--  Datenbank koennte da hineinsehen, aber jede einzelne Schreibpruefung
--  muesste dann durch dieses JSON laufen - teuer und zerbrechlich.
--
--  Es wird deshalb von der Seite geprueft, nicht von der Datenbank. Im
--  Klartext: wer seinen Code nimmt und mit einem eigenen Programm an der
--  Seite vorbei schreibt, kaeme daran vorbei. Bei Dingen, die sich
--  rueckgaengig machen lassen, ist das der richtige Preis - und ein
--  Mitglied, das so etwas tut, hat man ohnehin am falschen Ende.
--
--  Zum Notizbuch
--  -------------
--  priv:<player> enthaelt nur Zufall. Der Text wird im Browser mit einem
--  Schluessel verschluesselt, der aus dem persoenlichen Passwort entsteht
--  und das Geraet nie verlaesst. Auch wer die ganze Datenbank herunterlaedt,
--  liest dort nichts. Das ist keine Zusage, sondern Bauart.
-- ============================================================


-- ---------- Wer fuehrt ----------
-- Der Leiter steht als ganz normale Zeile in der Karte: meta:leader.
-- Steht dort niemand, fuehrt der Verwalter - sonst koennte den ersten
-- Leiter niemand ernennen und der Raum stuende ohne Fuehrung da.
create or replace function warmap_leader(r text) returns text
language sql stable security definer set search_path = public as $$
  select nullif(value->>'v', '') from warmap where room = r and key = 'meta:leader'
$$;

create or replace function warmap_ist_admin(r text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from warmap_member
                  where room = r and code = warmap_caller() and approved and is_admin)
$$;

create or replace function warmap_fuehrt(r text) returns boolean
language sql stable security definer set search_path = public as $$
  select case
    when warmap_leader(r) is null then warmap_ist_admin(r)
    else warmap_leader(r) = warmap_player(r)
  end
$$;


-- ---------- Schreibregeln ----------
-- Alles aus dem urspruenglichen Schema bleibt, es kommen nur Zeilen dazu.
-- Die Reihenfolge zaehlt: die neuen Faelle stehen vor dem "else true".
create or replace function warmap_may_write(r text, k text) returns boolean
language sql stable security definer set search_path = public as $$
  select case
    -- Zeilen, die ihren Verfasser im Schluessel tragen
    when k like 'depot:%' or k like 'priv:%' or k like 'wish:%' or k like 'sweep:%'
      then split_part(k, ':', 2) = warmap_player(r)
    when k like 'units:%' or k like 'join:%' or k like 'post:%' or k like 'line:%'
      or k like 'spot:%'  or k like 'area:%' or k like 'est:%' or k like 'first:%'
      then split_part(k, ':', 3) = warmap_player(r)

    -- Wer fuehrt, bestimmt der Verwalter. Sonst koennte ein Leiter, der den
    -- Clan verlaesst, das Amt mitnehmen und niemand kaeme mehr heran.
    when k = 'meta:leader'
      then warmap_ist_admin(r) or warmap_fuehrt(r)

    -- Die Entscheidungen, die den ganzen Clan binden
    when k in ('meta:rollen','meta:rang','meta:standrang','meta:clanf','meta:epoch')
      then warmap_fuehrt(r)

    else true
  end
$$;

grant execute on function warmap_leader(text)    to anon;
grant execute on function warmap_ist_admin(text) to anon;
grant execute on function warmap_fuehrt(text)    to anon;


-- ---------- Nachsehen ----------
--   select warmap_leader('dein-raum');
--   select name, is_admin, approved from warmap_member
--    where room = 'dein-raum' order by is_admin desc, lower(name);
--   select key, value->>'v' from warmap
--    where room = 'dein-raum' and key in ('meta:leader','meta:standrang');
--
-- Den Leiter notfalls von Hand setzen (die player-Kennung, nicht den Namen):
--   insert into warmap (room, key, value)
--        values ('dein-raum', 'meta:leader',
--                jsonb_build_object('v','abc123','t',(extract(epoch from now())*1000)::bigint))
--   on conflict (room, key) do update set value = excluded.value, updated_at = now();
