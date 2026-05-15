# data-dbt-artifacts

RND-interne modifizierte Version des open-source `dbt-artifacts` Packages.
Wird als lokale Dependency von `data-dbt-meta` eingebunden (`packages.yml: local: ../data-dbt-artifacts`).

## Zweck

Lädt dbt-Run-Ergebnisse (models, tests, invocations, etc.) per `on-run-end`-Hook in BigQuery-Tabellen.

## Einstiegspunkt

`macros/upload_results/upload_results.sql` — `upload_results(results)` Macro.
Wird in `data-dbt-meta/dbt_project.yml` aufgerufen:
```yaml
on-run-end:
  - "{% if target.name == 'prod' or var('run_dbt_artifacts', False) %} {{ dbt_artifacts.upload_results(results) }} {% endif %}"
```

## Welche Datasets werden geladen (Logik in upload_results.sql)

| Dataset | Bedingung |
|---------|-----------|
| `models` | Nur wenn `var('dbt_artifacts_upload_meta', False)` = true |
| `sources` | Gleiche Bedingung wie `models` |
| `seeds` | Gleiche Bedingung wie `models` |
| `snapshots` | Gleiche Bedingung wie `models` |
| `tests` | Nur wenn Tests im Run waren (`resource_type == "test"`) |
| `test_executions` | Gleiche Bedingung wie `tests` |

Vollständige Dataset-Liste (nicht alle aktiv): `['exposures', 'seeds', 'snapshots', 'invocations', 'sources', 'tests', 'models']`

## Wichtige Implementierungsdetails

**Jinja2-Einschränkung**: `selectattr` unterstützt kein `"containing"` für List-Membership. Falls Tag-Checks nötig: `namespace`-Pattern verwenden (kein `selectattr("containing")`)

**BigQuery chunk limits**: `models` → 50 rows/chunk, alle anderen → 300 rows/chunk.

**Relation-Check**: Vor dem Upload wird geprüft ob die Zieltabelle existiert.
Falls nicht: Compiler Error mit Hinweis `dbt run -s package:dbt_artifacts`.

## Deaktivierte Datasets

Ursprünglich wurden alle Datasets geladen. RND hat folgendes deaktiviert:
- `exposures`, `seeds`, `snapshots`, `invocations`, `sources` — nie in `datasets_to_load`
- `models` — war deaktiviert, jetzt bedingt aktiv (tag:meta)

## Vars (werden in data-dbt-meta gesetzt)

| Var | Wert | Zweck |
|-----|------|-------|
| `dbt_artifacts_exclude_all_results` | `True` | Verhindert Upload des kompletten Artifact-JSON (zu groß für BQ) |

## Makro-Struktur

```
macros/
├── upload_results/
│   ├── upload_results.sql          # Einstiegspunkt, steuert welche Datasets geladen werden
│   ├── get_dataset_content.sql     # Dispatcht auf upload_<dataset>.sql
│   ├── get_table_content_values.sql
│   ├── get_column_name_lists.sql
│   └── insert_into_metadata_table.sql
├── upload_individual_datasets/
│   ├── upload_models.sql
│   ├── upload_tests.sql
│   ├── upload_test_executions.sql
│   └── ... (exposures, seeds, snapshots, sources, invocations, model_executions, seed_executions, snapshot_executions)
└── database_specific_helpers/     # BigQuery-Adapter-Abstraktionen
```
