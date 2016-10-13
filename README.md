# postgrest-google-translate
PostgreSQL/PostgrREST proxy to Google Translate API, with caching. It allows to work with Google Translate API right from Postgres or via REST API calls.

[![Build Status](https://circleci.com/gh/NikolayS/postgrest-google-translate.png?style=shield&circle-token=fb58aee6e9f98cf85d08c4d382d5ba3f0f548e08)](https://circleci.com/gh/NikolayS/postgrest-google-translate/tree/master)

This tiny project consists of 2 parts:

1. SQL objects to enable calling Google API right from SQL environment (uses [plsh](https://github.com/petere/plsh) extension)
2. API method (uses [PostgREST](http://postgrest.com))

Part (1) can be used without part (2).

Table `google_translate.cache` is used to cache Google API responses to speedup work and reduce costs.

:warning: Limitations
---
In general, the idea to call external things (even pretty predictable and fast like Google API) might introduce significant limitations to capability to scale for your master. However, this project shows how powerful PostgreSQL is: you don't need to use PHP/Python/Java/Ruby to work with external JSON API.

To make it scalable, one could run PostgREST on multiple slave nodes to avoid this limitations. The ony thing is to think about – writing to `cache` table (TODO: check if it is possible to call master's wrinting functions from plpgsql code being executed on slave nodes).

Dependencies
---
1. cURL
2. [PostgREST](http://postgrest.com) – download the latest version. See `circle.yml` for example of starting/using it.
2. `plsh` – PostgreSQL extension, included to standard contribs package (install using `apt-get install postgresql-contrib-X.X` or `yum install ...`)

Installation
---
For your database (here we assume that it's called `dbname`), install [plsh](https://github.com/petere/plsh extension and then execute two SQL scripts, after what configure your database setting `google_translate.api_key` (take it from Google Could Platform Console):
```sh
psql dbname -c 'create extension if not exists plsh;'
psql dbname -f install_core.sql
psql dbname -f install_api.sql
psql -c "alter dbname set google_translate.api_key = 'YOU_GOOGLE_API_KEY';"
```

Alternatively, you can use `ALTER ROLE ... SET google_translate.api_key = 'YOU_GOOGLE_API_KEY';` or put this setting to `postgresql.conf` (in these cases, it will be available cluster-wide).

Uninstallation
---
```sh
psql dbname -f uninstall_api.sql
psql dbname -f uninstall_core.sql
psql dbname -c 'drop extension plsh;'
```

Usage
---
In SQL environment:
```sql
-- Translate from English to Russian
SELECT google_translate('en', 'ru', 'Hello world'); 
```

REST API:
```sh
curl -X POST -H "Content-Type: application/json" \
    -H "Cache-Control: no-cache" \
    -d '{"source": "en", "target": "ru", "q": "Hello world"}' \
    "http://localhost:3000/rpc/google_translate"
```
