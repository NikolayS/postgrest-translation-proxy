# postgrest-google-translate
PostgreSQL/PostgREST proxy to Google Translate API, with caching and ability to combine multiple text segments in one single request. It allows to work with Google Translate API right from Postgres or via REST API requests.

[![Build Status](https://circleci.com/gh/NikolayS/postgrest-google-translate.png?style=shield&circle-token=fb58aee6e9f98cf85d08c4d382d5ba3f0f548e08)](https://circleci.com/gh/NikolayS/postgrest-google-translate/tree/master)

This tiny project consists of 2 parts:

1. SQL objects to enable calling Google API right from SQL environment (uses [plsh](https://github.com/petere/plsh) extension)
2. API method (uses [PostgREST](http://postgrest.com))

Part (1) can be used without part (2).

Table `google_translate.cache` is used to cache Google API responses to speedup work and reduce costs.
Also, it is possible to combine multiple phrases in one API request, which provides great advantage (e.g.: for 10 uncached phrases, it will be ~150-200ms for single aggregated request versus 1.5-2 seconds for 10 consequent requests). Currently, Google Translate API accepts up to 128 text segments in a single request.

:warning: Limitations
---
In general, working with external things (even pretty predictable and fast like Google API) might introduce significant limitations to capability to scale for your master. However, this project shows how powerful PostgreSQL is: you don't need to use PHP/Python/Java/Ruby to work with external JSON API.

To make it scalable, one could run PostgREST on multiple slave nodes to avoid this limitations. The ony thing is to think about – writing to `cache` table (TODO: check if it is possible to call master's writing functions from plpgsql code being executed on slave nodes).

To minimize impact on the master node, it is a good idea to combine multiple text segments in a single request (see examples below).

It is worth to mention, that due to use of plsh and curl, a separate process (curl) is invoked on each non-cached request. Alternative approach is discussed in the [Issue #3](https://github.com/NikolayS/postgrest-google-translate/issues/3).

Also, see related notes ["Why This is a Bad Idea"](https://github.com/pramsey/pgsql-http#why-this-is-a-bad-idea)

Dependencies
---
1. cURL
2. [PostgREST](http://postgrest.com) – download the latest version. See `circle.yml` for example of starting/using it.
2. `plsh` – PostgreSQL contrib module, it is NOT included to standard contribs package. To install it on Ubuntu/Debian run: `apt-get install postgresql-X.X-plsh` (where X.X could be 9.5, depending on your Postgres version)

Installation
---
For your database (here we assume that it's called `DBNAME`), install [plsh](https://github.com/petere/plsh) extension and then execute two SQL scripts, after what configure your database setting `google_translate.api_key` (take it from Google Could Platform Console):
```sh
psql DBNAME -c 'create extension if not exists plsh;'
psql DBNAME -f install_core.sql
psql -c "alter DBNAME set google_translate.api_key = 'YOU_GOOGLE_API_KEY';"
```

Alternatively, you can use `ALTER ROLE ... SET google_translate.api_key = 'YOU_GOOGLE_API_KEY';` or put this setting to `postgresql.conf` (in these cases, it will be available cluster-wide).

To enable REST API proxy, install [PostgREST](http://postgrest.com), launch it (see `cirle.yml` as an example), and initialize API methods with the additional SQL script:
```sh
psql DBNAME -f install_api.sql
```

Uninstallation
---
```sh
psql DBNAME -f uninstall_api.sql
psql DBNAME -f uninstall_core.sql
psql DBNAME -c 'drop extension plsh;'
```

Usage
---
In SQL environment:
```sql
-- Translate from English to Russian
select google_translate.translate('en', 'ru', 'Hello world'); 

-- Combine multiple text segments in single query
select * from google_translate.translate('en', 'ru', array['ok computer', 'show me more','hello world!']);
```

REST API:
```sh
curl -X POST -H "Content-Type: application/json" \
    -H "Cache-Control: no-cache" \
    -d '{"source": "en", "target": "ru", "q": "Hello world"}' \
    "http://localhost:3000/rpc/google_translate"
```

```sh
curl -X POST -H "Content-Type: application/json" \
    -H "Cache-Control: no-cache" \
    -d '{"source": "en", "target": "ru", "q": ["ok computer", "hello world", "yet another phrase"]}' \
    "https://localhost:3000/rpc/google_translate_array"
```
