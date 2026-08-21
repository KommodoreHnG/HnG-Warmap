-- ############################################################
--  ARCHIV - NICHT MEHR AUSFUEHREN
-- ############################################################
--
--  Bis zum 21.08.2026 war dies der gueltige Stand. In der Nacht auf den
--  22.08. kamen vier Wanderungen dazu, die diese Datei nicht kennt:
--    zeitstempel_nur_bei_echter_aenderung
--    pruefspur_nichts_verschwindet_spurlos
--    nur_objekte_sonst_faellt_der_schutz_aus
--    mengenbremse_gegen_vollschreiben
--
--  Wer sie ausfuehrt, dreht den Ausloeser auf die Fassung zurueck, bei der
--  ein Wert ohne Objektform den gesamten Schutz aushebelte - samt
--  Zeugenpruefung fuer die Soldatenlisten.
--
--  ES GIBT JETZT KEINE STANDDATEI MEHR. Die Regeln leben in der Datenbank,
--  Supabase fuehrt die Wanderungen selbst. Siehe DATENBANK-LIESMICH.md im
--  Hauptordner.
--
--  Archiviert am 22.08.2026.
-- ############################################################
do $ARCHIVRIEGEL$
begin
  raise exception
    'ARCHIV: % darf nicht ausgefuehrt werden. Die Regeln leben in der Datenbank - siehe DATENBANK-LIESMICH.md.',
    'supabase_stand_2026-08-21.sql';
end
$ARCHIVRIEGEL$;

-- ============================================================================
--  DER LAUFENDE STAND, ausgelesen am 21. August 2026 aus pg_proc.prosrc,
--  danach an EINER Stelle geaendert.
--
--  DIESE DATEI UEBERHOLT supabase_bestaetigen.sql.
--
--  Warum es sie gibt: die aelteren Dateien im Ordner geben nicht mehr wieder,
--  was in der Datenbank steht. Gezaehlt:
--
--      supabase_bestaetigen.sql     4 Zweige
--      laufende Datenbank          10 Zweige
--
--  Sechs Regeln standen also nur noch in der Datenbank. Und weil
--  warmap_may_write mit "create or replace" geschrieben wird - das den
--  GANZEN Rumpf ersetzt -, haette jede Wanderung, die aus einer der alten
--  Dateien abgeleitet ist, diese sechs stillschweigend geloescht. Kein
--  Fehler, keine Meldung; nur waeren danach spot:, est:, first:, roster:,
--  edep:, arrow:, gone: und die drei meta-Zweige nicht mehr geschuetzt.
--
--  Wer hier etwas aendert, geht von DIESER Fassung aus.
--
--  ---- DIE EINE AENDERUNG: para: ist kein Freiwild mehr ----
--
--  line: und area: tragen den Verfasser im Schluessel und sind dadurch
--  geschuetzt. para: hat nur die Stadtnummer - und fiel deshalb auf
--  "else true", obwohl es genauso ein Befehl ist. Jeder im Raum konnte den
--  Parablock eines anderen ueberschreiben.
--
--  Heute noch ohne Wirkung (null para-Zeilen in der Tabelle), aber die
--  Auswertung dafuer steht seit dem 21.08. im Werkzeug, also wird es genutzt
--  werden. Geregelt nach dem Muster von arrow:, das dasselbe Problem hat -
--  Eigentum in der Zeile statt im Schluessel: wer 'loeschen' darf, darf
--  fremde aendern; sonst nur neu anlegen oder den eigenen.
--
--  Geprueft gegen die alte Fassung ueber jeden vorkommenden und jeden
--  denkbaren Schluessel: genau eine Entscheidung aendert sich.
--
--      para: fremder Eintrag     vorher erlaubt, jetzt abgewiesen
--      para: neu anlegen         unveraendert erlaubt
--      alles andere              unveraendert
--
--  ---- WAS VERSUCHT UND VERWORFEN WURDE ----
--
--  Die bewusst offenen Eimer (owner:, fight:, vers:, star:, notes:, btl:,
--  akt:, todo:) an den Anfang zu ziehen, damit der haeufigste Fall nicht alle
--  zehn Zweige durchlaeuft. Klingt schneller, ist es aber nicht - ueber sechs
--  Durchgaenge an den 903 Zeilen der laufenden Tabelle gemessen:
--
--      wie unten                29,4 ms
--      mit vorgezogenem Block   37,3 ms
--
--  Neun like-Muster in einem Zweig kosten mehr, als zehn schnell
--  fehlschlagende Zweige sparen. Die Absicht, die dabei sichtbar geworden
--  waere, steht jetzt als Kommentar bei "else true" - zum Nulltarif.
--
--  ---- WAS ABSICHTLICH NICHT GEAENDERT WURDE ----
--
--  anon: hat keine Regel hier und braucht keine. Der Trigger warmap_stempeln
--  schuetzt es ueber die Spalte zeuge: wer eine fremde Liste aendern will,
--  bekommt "Diese Liste gehoert jemand anderem". Eine zweite Regel an dieser
--  Stelle waere Guertel und Hosentraeger und wuerde beim naechsten Lesen die
--  Frage aufwerfen, welche der beiden gilt.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.warmap_may_write(r text, k text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case
    -- Eigenes: Verfasser steht im Schluessel
    when k like 'depot:%' or k like 'priv:%' or k like 'wish:%' or k like 'sweep:%'
      then split_part(k, ':', 2) = warmap_player(r)
    when k like 'units:%' or k like 'join:%' or k like 'post:%' or k like 'line:%'
      or k like 'area:%'
      then split_part(k, ':', 3) = warmap_player(r)

    -- Aufklaerung mit Verfasser im Schluessel: eigenes UND das Recht dazu
    when k like 'spot:%' or k like 'est:%' or k like 'first:%'
      then split_part(k, ':', 3) = warmap_player(r)
       and warmap_darf(r, 'aufklaerung')

    -- Aufklaerung ohne Verfasser im Schluessel: nur das Recht
    when k like 'roster:%' or k like 'edep:%'
      then warmap_darf(r, 'aufklaerung')

    -- Pfeile tragen ihr Eigentum in der Zeile, nicht im Schluessel
    when k like 'arrow:%'
      then warmap_darf(r, 'loeschen')
        or not exists (select 1 from warmap w where w.room = r and w.key = k)
        or exists (select 1 from warmap w
                    where w.room = r and w.key = k
                      and coalesce(w.value->'v'->>'by', w.value->>'by')
                          = warmap_player(r))

    -- Parablock: derselbe Fall wie der Pfeil. Der Schluessel traegt nur die
    -- Stadt, also muss das Eigentum aus der Zeile kommen. Ohne diesen Zweig
    -- fiel para: auf "else true", und jeder konnte den Block eines anderen
    -- ueberschreiben - waehrend line: und area: nebenan geschuetzt sind.
    when k like 'para:%'
      then warmap_darf(r, 'loeschen')
        or not exists (select 1 from warmap w where w.room = r and w.key = k)
        or exists (select 1 from warmap w
                    where w.room = r and w.key = k
                      and coalesce(w.value->'v'->>'by', w.value->>'by')
                          = warmap_player(r))

    -- Einen Eintrag von der Karte nehmen: eigenes, oder mit dem Recht dazu
    when k like 'gone:%'
      then warmap_darf(r, 'loeschen')
        or split_part(k, ':', 3) = warmap_player(r)
        or exists (select 1 from warmap w
                    where w.room = r
                      and w.key  = 'arrow:' || substr(k, 6)
                      and coalesce(w.value->'v'->>'by', w.value->>'by')
                          = warmap_player(r))

    when k like 'ok:%'
      then warmap_darf(r, 'bestaetigen')

    -- ---- Der Krieg selbst: nur der Verwalter ----
    when k in ('meta:epoch', 'meta:war', 'meta:start')
      then warmap_ist_admin(r)

    -- Wer fuehrt, bestimmt der Verwalter - sonst koennte ein Leiter, der den
    -- Clan verlaesst, das Amt mitnehmen und niemand kaeme mehr heran.
    when k = 'meta:leader'
      then warmap_ist_admin(r) or warmap_fuehrt(r)

    -- Alles Uebrige unter meta: ist Clansache
    when k like 'meta:%'
      then warmap_fuehrt(r)

    -- ---- Hier landen absichtlich ----
    --   owner:, fight:, vers:   gelesene Beobachtungen. Wer im Raum ist, darf
    --                           sie eintragen: eine abgelesene Stadtfarbe
    --                           gehoert niemandem.
    --   star:, notes:, btl:     gemeinsame Markierungen und Notizen.
    --   akt:, todo:             Aufgaben des Clans.
    --   anon:                   ueber den Trigger und die Spalte zeuge
    --                           geschuetzt, nicht hier.
    --
    -- Und alles, was das Werkzeug spaeter dazubekommt. Offen zu lassen ist
    -- hier die richtige Wahl: neue Eimer entstehen schneller, als Wanderungen
    -- ausgerollt werden, und ein stillschweigend abgewiesener Eintrag faellt
    -- beim Nutzer als "Sync tut nichts" auf, nicht als Fehler.
    else true
  end
$function$;
