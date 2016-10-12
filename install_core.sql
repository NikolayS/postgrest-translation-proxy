begin;

create schema google_translate;

create or replace function google_translate.urlencode(in_str text, out _result text) returns text as $$
declare
    _i      int4;
    _temp   varchar;
    _ascii  int4;
begin
    _result := '';
    for _i in 1 .. length(in_str) loop
        _temp := substr(in_str, _i, 1);
        if _temp ~ '[0-9a-za-z:/@._?#-]+' then
            _result := _result || _temp;
        else
            _ascii := ascii(_temp);
            if _ascii > x'07ff'::int4 then
                raise exception 'Won''t deal with 3 (or more) byte sequences.';
            end if;
            if _ascii <= x'07f'::int4 then
                _temp := '%'||to_hex(_ascii);
            else
                _temp := '%'||to_hex((_ascii & x'03f'::int4)+x'80'::int4);
                _ascii := _ascii >> 6;
                _temp := '%'||to_hex((_ascii & x'01f'::int4)+x'c0'::int4)
                            ||_temp;
            end if;
            _result := _result || upper(_temp);
        end if;
    end loop;
    return ;
end;
$$ language plpgsql;

create table google_translate.cache(
    source char(2) not null,
    target char(2) not null,
    q text not null,
    result text not null,
    created timestamp not null default now(),
    primary key(q, source, target)
);

comment on table google_translate.cache is 'Cache for Google Translate API calls';

create or replace function google_translate._translate_curl(text, char(2), char(2), text) returns json as $$
#!/bin/sh
curl -H "Accept: application/json" "https://www.googleapis.com/language/translate/v2?key=$1&source=$2&target=$3&q=$4" 2>/dev/null | sed 's/\r//g'
$$ language plsh;

create or replace function google_translate.translate(api_key text, source char(2), target char(2), q text) returns text as $$
declare
    qtrimmed text;
    response json;
    res text;
begin
    qtrimmed = trim(translate.q);
    res := null;
    select into res 
        result
    from 
        google_translate.cache gt
    where 
        gt.source = translate.source
        and gt.target = translate.target
        and gt.q = qtrimmed;

    if not found then
        raise notice 'Calling Google Translate API for source=%, target=%, q=%...', source, target, left(qtrimmed, 15);
        select into response google_translate._translate_curl(api_key, source, target, google_translate.urlencode(qtrimmed));
        if response->'error'->'message' is not null then
            raise exception 'Google API responded with error: %', response->'error'->'message'::text
                using detail = jsonb_pretty((response->'error'->'errors')::jsonb);
        elsif response->'data'->'translations'->0->'translatedText' is not null then
            res := response->'data'->'translations'->0->'translatedText'::text;
            res := regexp_replace(res, '"$|^"', '', 'g');
            if res <> '' then
                insert into google_translate.cache(source, target, q, result)
                    values(translate.source, translate.target, qtrimmed, res);
            else
                raise exception 'Cannot parase Google API''s response properly';
            end if;
        else 
            raise exception 'Cannot parase Google API''s response properly';
        end if;
    end if;

    return res;
end;
$$ language plpgsql;

create or replace function google_translate.translate(source char(2), target char(2), q text) returns text as $$
begin
    if current_setting('google_translate.api_key') is null or current_setting('google_translate.api_key') = '' then
        raise exception 'Configuration error: google_translate.api_key has not been set';
    end if;
    return google_translate.translate(current_setting('google_translate.api_key')::text, source, target, q);
end;
$$ language plpgsql;

commit;
