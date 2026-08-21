# Altstaende der Datenbankregeln

Hier liegen die SQL-Dateien, die den Server frueher eingerichtet haben. Sie
sind **Lesestoff, kein Werkzeug**.

## Warum sie nicht mehr ausgefuehrt werden duerfen

Die Schreibrechte des Servers stecken in einer einzigen Funktion. Jede dieser
Dateien enthaelt eine vollstaendige Fassung davon - und `create or replace`
ersetzt immer den ganzen Inhalt. Es gibt kein Zusammenfuehren.

Wer eine alte Datei ausfuehrt, wirft also alles weg, was seit ihrer
Entstehung dazugekommen ist. Das Tueckische daran: der Schaden zeigt sich
nicht als Fehlermeldung. Eine fehlende Regel bedeutet nicht "verboten",
sondern **"erlaubt"**. Der Server wird stiller und offener zugleich - und
niemand merkt es, bis jemand es ausnutzt.

Gemessen am 21.08.2026: `supabase_bestaetigen.sql` kennt 5 Regelzweige, der
laufende Server 11. Ueber 37 gepruefte Faelle ergaben sich 13 Abweichungen.

## Der Riegel

Jede Datei hier beginnt jetzt mit einem Abbruch. Landet sie doch einmal im
SQL-Editor, bricht sie mit einer Meldung ab, bevor irgendetwas passiert.

## Wo der gueltige Stand steht

**In der Datenbank, nicht in einer Datei.** Supabase fuehrt die Wanderungen
(Migrationen) selbst - am 22.08.2026 waren es 23. Wie man sie ansieht, steht
in `DATENBANK-LIESMICH.md` im Hauptordner.

Die frueheren Standdateien liegen hier mit im Archiv. Auch sie duerfen nicht
mehr ausgefuehrt werden.

## Regel fuer die Zukunft

Aenderungen an den Serverregeln laufen **nur** als Wanderung. Keine Datei in
diesem Ordner ist je wieder "der Stand" - genau diese Doppelfuehrung war das
Problem. Wer trotzdem eine .sql-Datei anlegt, gibt ihr einen Kopf, der die
Ausfuehrung abbricht.

## Was hier liegt

- **supabase_bestaetigen.sql** - Fuehrte das Recht 'bestaetigen' ein. may_write mit 5 Zweigen - 13 gemessene Abweichungen zum Live-Stand.
- **supabase_mitglieder.sql** - Legte die Mitgliederverwaltung an (warmap_ich, invite_me, members, member_set, member_drop). Diese Funktionen laufen heute live; die Datei koennte einen aelteren Stand tragen.
- **supabase_nachtrag.sql** - Nachtrag zum ersten Aufbau. may_write mit 2 Zweigen.
- **supabase_neuercode.sql** - Legte warmap_recode an - eine Funktion, die live GAR NICHT existiert. Wurde also nie eingespielt oder wieder entfernt.
- **supabase_rollen.sql** - Fuehrte die Rollen ein. may_write mit 4 Zweigen.
- **supabase_schema.sql** - Der erste Aufbau. Legt Tabelle, Policies UND warmap_may_write neu an - mit 2 statt 11 Zweigen. Wuerde den kompletten Regelsatz zuruecksetzen.
