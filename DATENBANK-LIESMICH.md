# Wo die Regeln des Servers wohnen

Kurz: **in der Datenbank, nicht in diesem Ordner.**

## Warum das wichtig ist

Wer auf dem Server was ändern darf, steht in einer einzigen Regelliste. Diese
Liste lässt sich nicht ergänzen — man kann sie nur **komplett ersetzen**. Wer
eine Regel hinzufügen will, schreibt die ganze Liste neu.

Daraus folgt die Gefahr: Führt jemand eine Fassung von letzter Woche aus, sind
alle Regeln von dieser Woche weg. Nicht fehlerhaft, sondern *weg* — und was
fehlt, fällt auf den Auffangsatz „alles Übrige ist erlaubt". **Eine verlorene
Regel verbietet nie etwas, sie erlaubt.** Es gibt keine Fehlermeldung, und
niemand merkt es, bis jemand es ausnutzt.

Genau das lag hier herum: sechs Dateien, jede mit einer vollständigen Fassung
der Regelliste, vier davon veraltet. Im Kopf jeder stand „Gefahrlos mehrfach
ausführbar". Das stimmte einmal.

## Wie es jetzt läuft

Jede Änderung an den Regeln ist eine **Wanderung** (Migration) und wird von
Supabase selbst mit Zeitstempel und Namen geführt. Am 22.08.2026 waren es 23
Stück. Die Datenbank ist damit ihre eigene Wahrheit — kein Dokument daneben,
das veralten kann.

**Den aktuellen Stand ansehen:**

Im SQL-Editor von Supabase:

```sql
select version, name from supabase_migrations.schema_migrations
 order by version;
```

**Eine einzelne Regel im Volltext lesen:**

```sql
select pg_get_functiondef(p.oid)
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = 'warmap_may_write';
```

**Alles auf einmal, zum Sichern:**

```sql
select string_agg(pg_get_functiondef(p.oid), E';\n\n' order by p.proname)
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname like 'warmap%';
```

## Die Regel für die Zukunft

Änderungen an den Serverregeln laufen **nur** als Wanderung. Nie über eine
Datei in diesem Ordner, nie durch Einfügen in den SQL-Editor von Hand.

Wer trotzdem eine `.sql`-Datei anlegt, gibt ihr einen Kopf, der die Ausführung
abbricht — so wie die Dateien in `sql_archiv/`.

## Was in sql_archiv/ liegt

Sieben alte Dateien, jede mit einer Sperre am Anfang, die beim Ausführen
abbricht. Sie sind **Lesestoff**: man kann darin nachsehen, wie etwas früher
aussah. Ausführen darf man sie nicht.

## Die Prüfspur

Seit dem 22.08.2026 schreibt der Server jede echte Änderung mit: wer, wann,
was vorher drinstand. Die Tabelle heißt `warmap_spur` und ist von außen für
niemanden erreichbar — nur über den direkten Datenbankzugang.

Einen Massenschaden zurückholen: das Rezept steht als Kommentar in der
Wanderung `pruefspur_nichts_verschwindet_spurlos`. Es gibt bewusst **keinen
Knopf** dafür, denn ein solcher Knopf wäre selbst eine Waffe.
