-- Promt API

-- api_key, source lang, target lang, text
create or replace function translation_proxy._promt_translate_curl(text, char(2), char(2), text) returns text as $$
#!/bin/sh
curl --connect-timeout 2 -H "Accept: application/json" "https://www.googleapis.com/language/translate/v2?key=$1&source=$2&target=$3&q=$4" 2>/dev/null | sed 's/\r//g'
$$ language plsh;

create or replace function translation_proxy.promt_translate(api_key text, source char(2), target char(2), qs text[]) returns text[] as $$
begin
end;
$$ language plpgsql;

create or replace function translation_proxy.promt_translate(source char(2), target char(2), qs text[]) returns text[] as $$
begin
end;
$$ language plpgsql;

create or replace function translation_proxy.promt_translate(source char(2), target char(2), q text) returns text as $$
begin
end;
$$ language plpgsql;

create or replace function translation_proxy.promt_translate_array(source char(2), target char(2), q json) returns text[] as $$
begin
end;
$$ language plpgsql;
