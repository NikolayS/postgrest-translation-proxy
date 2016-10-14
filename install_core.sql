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
                --raise exception 'Won''t deal with 3 (or more) byte sequences.';
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

create or replace function google_translate.translate(api_key text, source char(2), target char(2), qs text[]) returns text[] as $$
declare
    qs2call text[];
    i2call int4[];
    q2call_urlencoded text;
    response json;
    resp_1 json;
    res text[];
    k int4;
    rec record;
begin
    res := qs; -- by default, return input "as is"
    qs2call := array[]::text[];
    i2call := array[]::int4[];
    q2call_urlencoded := '';
    
    for rec in
        with subs as (
            select generate_subscripts as i from generate_subscripts(qs, 1)
        ), queries as(
            select i, qs[i] as q
            from subs
        )
        select 
            queries.i as i,
            result,
            trim(queries.q) as q
        from 
            google_translate.cache 
        right join queries on trim(queries.q) = cache.q
            and cache.source = translate.source
            and cache.target = translate.target
    loop
        raise debug 'INTPUT: i: %, q: "%", result found in cache: "%"', rec.i, rec.q, rec.result;
        if rec.result is not null then
            res[rec.i] := rec.result;
        else
            qs2call = array_append(qs2call, trim(rec.q));
            i2call = array_append(i2call, rec.i);
            if q2call_urlencoded <> '' then
                q2call_urlencoded := q2call_urlencoded || '&q=';
            end if;
            q2call_urlencoded := q2call_urlencoded || google_translate.urlencode(trim(rec.q)); 
        end if;
    end loop;
    raise debug 'TO PASS TO GOOGLE API: qs2call: %, i2call: %', array_to_string(qs2call, '*'), array_to_string(i2call, '-');
    raise debug 'URLENCODED STRING: %', q2call_urlencoded; 

    --return res;
    
    if q2call_urlencoded <> '' then
        raise debug 'Calling Google Translate API for source=%, target=%, q=%', source, target, q2call_urlencoded;
        select into response google_translate._translate_curl(api_key, source, target, q2call_urlencoded);
        if response->'error'->'message' is not null then
            raise exception 'Google API responded with error: %', response->'error'->'message'::text
                using detail = jsonb_pretty((response->'error'->'errors')::jsonb);
        elsif response->'data'->'translations'->0->'translatedText' is not null then
            k := 1;
            for resp_1 in select * from json_array_elements(response->'data'->'translations')
            loop
                res[i2call[k]] := regexp_replace((resp_1->'translatedText')::text, '"$|^"', '', 'g');
                if res[i2call[k]] <> '' then
                    insert into google_translate.cache(source, target, q, result)
                    values(translate.source, translate.target, qs2call[k], res[i2call[k]])
                    on conflict do nothing;
                else
                    raise exception 'Cannot parse Google API''s response properly';
                end if;
                k := k + 1;
            end loop;
        else 
            raise exception 'Cannot parase Google API''s response properly';
        end if;
    end if;

    return res;
end;
$$ language plpgsql;

create or replace function google_translate.translate(source char(2), target char(2), qs text[]) returns text[] as $$
begin
    if current_setting('google_translate.api_key') is null or current_setting('google_translate.api_key') = '' then
        raise exception 'Configuration error: google_translate.api_key has not been set';
    end if;

    return google_translate.translate(current_setting('google_translate.api_key')::text, source, target, qs);
end;
$$ language plpgsql;

create or replace function google_translate.translate(source char(2), target char(2), q text) returns text as $$
declare
    res text[];
begin
raise notice 'TEXT-TYPED q: %', q;
    if current_setting('google_translate.api_key') is null or current_setting('google_translate.api_key') = '' then
        raise exception 'Configuration error: google_translate.api_key has not been set';
    end if;
    select into res translate
    from google_translate.translate(current_setting('google_translate.api_key')::text, source, target, ARRAY[q]);

    return res[1];
end;
$$ language plpgsql;

create or replace function google_translate.translate(source char(2), target char(2), q json) returns text[] as $$
declare
    res text[];
    qs text[];
begin
raise notice 'JSON-TYPED q: %', q;
    if current_setting('google_translate.api_key') is null or current_setting('google_translate.api_key') = '' then
        raise exception 'Configuration error: google_translate.api_key has not been set';
    end if;

    select into qs array(select * from json_array_elements_text(q));

    select into res translate
    from google_translate.translate(current_setting('google_translate.api_key')::text, source, target, qs);

    return res;
end;
$$ language plpgsql;
