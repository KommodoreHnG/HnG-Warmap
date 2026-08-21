-- ############################################################
--  ARCHIV - NICHT MEHR AUSFUEHREN
-- ############################################################
--
--  Fuehrte das Recht 'bestaetigen' ein. may_write mit 5 Zweigen - 13 gemessene Abweichungen zum Live-Stand.
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
    'supabase_bestaetigen.sql';
end
$ARCHIVRIEGEL$;

-- ============================================================
--  Bestaetigen ist eine Entscheidung, keine Notiz
--  Einmal im SQL-Editor von Supabase ausfuehren.
--  Aendert keine Daten, nur Regeln. Gefahrlos mehrfach ausfuehrbar.
-- ============================================================
--
--  Worum es geht
--  -------------
--  Der Topf ok:<id> entscheidet, ob aus einem Vorschlag ein BEFEHL wird.
--  Die Seite prueft dafuer das Recht "bestaetigen" - aber nur die Seite:
--
--      function setBestaetigt(id, an){
--        if (!darf("bestaetigen")) return darfNicht("bestaetigen");
--        stamp("ok", id, an ? 1 : null, ...);
--      }
--
--  In der Datenbank fiel ok: bisher unter "else true". Wer die Seite mit den
--  Entwicklerwerkzeugen anfasst oder die Schnittstelle direkt aufruft, macht
--  damit seinen eigenen Vorschlag zum Clanbefehl. Der Schluessel traegt auch
--  keinen Verfasserteil, also greift die Verfasserregel nicht.
--
--  Warum ausgerechnet dieser Topf
--  ------------------------------
--  supabase_rollen.sql begruendet ausdruecklich, warum Rangrechte NICHT in
--  der Datenbank geprueft werden: jede Schreibpruefung muesste durch das
--  JSON in meta:rollen laufen, das ist teuer und zerbrechlich. Und bei
--  Dingen, die sich zurueckdrehen lassen, ist das der richtige Preis.
--
--  Bei ok: traegt diese Begruendung nicht:
--
--    - Der Schaden entsteht, wenn Leute AUSRUECKEN. Ein spaeteres
--      Zurueckdrehen holt niemanden zurueck.
--    - Es ist genau EIN Topf, und er wird selten geschrieben - ein Leiter
--      bestaetigt ein paar Mal am Tag, nicht hundertmal in der Minute.
--      Die Kostenfrage stellt sich hier nicht.
--
--  Alle anderen Toepfe bleiben, wie sie sind.
-- ============================================================


-- ---------- Welche Raenge hat jemand ----------
-- meta:rang ist eine Zuordnung Spieler -> Liste von Rangkennungen.
-- Wer keine zugeteilt bekommen hat, faellt auf meta:standrang zurueck -
-- sonst duerfte ein frisch Eingeladener gar nichts.
-- ACHTUNG: array(select jsonb_array_elements_text(NULL)) liefert ein LEERES
-- Array, nicht NULL. Ohne das nullif greift das coalesce nie, und wer keinen
-- Rang zugeteilt bekommen hat, bekommt eine leere Liste statt des Vorgaberangs.
-- Beim Nachmessen an der laufenden Datenbank aufgefallen.
create or replace function warmap_meine_raenge(r text) returns text[]
language sql stable security definer set search_path = public as $$
  select coalesce(
    nullif(
      (select array(select jsonb_array_elements_text(
                (select value->'v'->warmap_player(r) from warmap
                  where room = r and key = 'meta:rang')))),
      '{}'::text[]),
    array[ coalesce(
      (select value->>'v' from warmap where room = r and key = 'meta:standrang'),
      'mem') ]
  )
$$;

-- ---------- Darf jemand etwas ----------
-- Der Leiter darf alles. Sonst zaehlt, ob einer seiner Raenge das Recht
-- traegt. Fehlt meta:rollen, gelten dieselben drei Vorgaberollen wie in der
-- Seite - sonst wuerde ein Raum, in dem nie Raenge angelegt wurden, alles
-- verweigern.
create or replace function warmap_darf(r text, recht text) returns boolean
language sql stable security definer set search_path = public as $$
  select case
    when warmap_fuehrt(r) then true
    else exists (
      select 1
        from jsonb_array_elements(
               coalesce(
                 (select value->'v' from warmap where room = r and key = 'meta:rollen'),
                 '[{"id":"off","rechte":{"befehl":1,"bestaetigen":1,"loeschen":1,
                                          "hilfe":1,"brett":1,"aufklaerung":1}},
                    {"id":"sqd","rechte":{"hilfe":1,"brett":1,"aufklaerung":1}},
                    {"id":"mem","rechte":{"brett":1,"aufklaerung":1}}]'::jsonb)
             ) as rolle
       where rolle->>'id' = any (warmap_meine_raenge(r))
         and coalesce(rolle->'rechte'->>recht, '0') not in ('0', 'false', '')
    )
  end
$$;

grant execute on function warmap_meine_raenge(text) to anon;
grant execute on function warmap_darf(text, text)   to anon;


-- ---------- Die Schreibregel ----------
-- Unveraendert uebernommen aus supabase_rollen.sql, mit EINER neuen Zeile
-- fuer ok:. Die Reihenfolge zaehlt - der neue Fall steht vor dem "else true".
create or replace function warmap_may_write(r text, k text) returns boolean
language sql stable security definer set search_path = public as $$
  select case
    -- Zeilen, die ihren Verfasser im Schluessel tragen
    when k like 'depot:%' or k like 'priv:%' or k like 'wish:%' or k like 'sweep:%'
      then split_part(k, ':', 2) = warmap_player(r)
    when k like 'units:%' or k like 'join:%' or k like 'post:%' or k like 'line:%'
      or k like 'spot:%'  or k like 'area:%' or k like 'est:%' or k like 'first:%'
      then split_part(k, ':', 3) = warmap_player(r)

    -- NEU: aus einem Vorschlag einen Befehl machen darf nur, wer das Recht hat
    when k like 'ok:%'
      then warmap_darf(r, 'bestaetigen')

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


-- ---------- Der Trigger entschied ebenfalls nach Client-Zeit ----------
-- Erst der Datenbankzugriff hat das sichtbar gemacht: warmap_keep_newest
-- verglich den mitgeschickten Zeitstempel und verwarf jeden Schreibvorgang
-- mit kleinerem t STILLSCHWEIGEND:
--
--   if coalesce((new.value->>'t')::bigint, 0) < coalesce((old.value->>'t')::bigint, 0)
--     then return old;
--
-- Eine Zeile mit dem Jahr 2100 war damit dauerhaft unbeschreibbar - kein
-- Leiter, kein Nachfolger konnte sie korrigieren. Und es traf auch ohne
-- Absicht: eine vorgehende Uhr in einer anderen Zeitzone genuegte.
--
-- Die Reihenfolge kommt jetzt allein aus updated_at, das der Server setzt.
create or replace function warmap_keep_newest()
returns trigger language plpgsql set search_path = public as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- Hygiene: SECURITY INVOKER, das Risiko ist gering - aber jede andere
-- Funktion hier hat den search_path festgenagelt.
create or replace function warmap_caller() returns text
language sql stable set search_path = public as $$
  select nullif(current_setting('request.headers', true)::json->>'x-warmap-code', '')
$$;


-- ---------- Nachsehen ----------
--  Wer darf bestaetigen (mit dem eigenen Code im Header aufrufen):
--    select warmap_meine_raenge('dein-raum');
--    select warmap_darf('dein-raum', 'bestaetigen');
--
--  Gegenprobe, dass die Regel greift - muss FALSE liefern, wenn der Code
--  eines einfachen Mitglieds im Header steht:
--    select warmap_may_write('dein-raum', 'ok:irgendeine-id');
--
--  Und dass eine vergiftete Zeile wieder korrigierbar ist:
--    begin;
--    insert into warmap (room, key, value)
--         values ('__probe__', 'est:1:x', jsonb_build_object('v','x','t', 4102444800000))
--      on conflict (room, key) do update set value = excluded.value;
--    update warmap set value = jsonb_build_object('v','korrektur','t', 1000)
--     where room='__probe__' and key='est:1:x';
--    select value->>'v' from warmap where room='__probe__';   -- muss 'korrektur' sein
--    rollback;
--
--  Am 2026-08-20 gegen die laufende Datenbank ausgefuehrt und geprueft.
