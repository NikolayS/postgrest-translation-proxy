create schema google_translate;

--create or replace function public.urlencode(in_str text, out _result text) returns text as $$                                                                                                        select                                                                                                                                                                                               string_agg(                                                                                                                                                                                          case                                                                                                                                                                                                 when ol>1 or ch !~ '[0-9a-za-z:/@._?#-]+'                                                                                                                                                            then regexp_replace(upper(substring(ch::bytea::text, 3)), '(..)', E'%\\1', 'g')                                                                                                              else ch                                                                                                                                                                                      end,
--            ''
--        )
--    from (
--        select ch, octet_length(ch) as ol
--        from regexp_split_to_table($1, '') as ch
--    ) as s;
--$$ language sql immutable strict;

-- Disclaimer: this urlencode is unusual -- it doesn't touch most chars (incl. multibytes)
-- to avoid reaching 2K limit for URL in Google API calls.
-- "Regular" urlencode() with multibyte chars support is shown above (commented out block of code). 
create or replace function google_translate.urlencode(text) returns text as $$
    select 
        string_agg(
            case
                when ascii(ch) in (32, 160) then -- space
                    '+'
                when ol=1 and ch ~ '[+\]\[%&#]+'  -- this is not traditional urlencode!
                    then regexp_replace(upper(substring(ch::bytea::text, 3)), '(..)', E'%\\1', 'g')
                else 
                    ch
            end, 
            ''
        )
    from (
        select ch, octet_length(ch) as ol
        from regexp_split_to_table($1, '') as ch
    ) as s;
$$ language sql immutable strict;

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
curl --connect-timeout 2 -H "Accept: application/json" "https://www.googleapis.com/language/translate/v2?key=$1&source=$2&target=$3&q=$4" 2>/dev/null | sed 's/\r//g'
$$ language plsh;

create or replace function google_translate.translate(api_key text, source char(2), target char(2), qs text[]) returns text[] as $$
declare
    qs2call text[];
    i2call int4[];
    q2call_urlencoded text;
    url_len int4;
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
        raise debug 'INPUT: i: %, q: "%", result found in cache: "%"', rec.i, rec.q, rec.result;
        if rec.result is not null then
            res[rec.i] := rec.result;
        elsif (current_setting('google_translate.begin_at') is not null 
                            and current_setting('google_translate.begin_at')::timestamp > current_timestamp
              ) or (current_setting('google_translate.end_at') is not null
                            and current_setting('google_translate.end_at')::timestamp < current_timestamp
              ) then
            res[rec.i] := rec.q;
        else
            qs2call = array_append(qs2call, trim(rec.q));
            i2call = array_append(i2call, rec.i);
            if q2call_urlencoded <> '' then
                q2call_urlencoded := q2call_urlencoded || '&q=';
            end if;
            q2call_urlencoded := q2call_urlencoded || replace(google_translate.urlencode(trim(rec.q)), ' ', '+');
        end if;
    end loop;
    raise debug 'TO PASS TO GOOGLE API: qs2call: %, i2call: %', array_to_string(qs2call, '*'), array_to_string(i2call, '-');
    raise debug 'URLENCODED STRING: %', q2call_urlencoded;

    if q2call_urlencoded <> '' then
        --q2call_urlencoded := replace(q2call_urlencoded, ' ', '+');
        url_len := length(q2call_urlencoded);
        raise debug 'q2call_urlencoded length=%, total URL length=%', url_len, (url_len + 115);
        if url_len > 1885 then
            raise exception 'Google API''s character limit (2K) is exceeded, total URL length=%', (url_len + 115);
        end if;
        raise info 'Calling Google Translate API for source=%, target=%, q=%', source, target, q2call_urlencoded;
        select into response google_translate._translate_curl(api_key, source, target, q2call_urlencoded);
        if response is null then
            raise exception 'Google API responded with empty JSON';
        elsif response->'error'->'message' is not null then
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
                    raise exception 'Cannot parse Google API''s response properly (see Details to check full "response" JSON)'
                        using detail = jsonb_pretty(response::jsonb);
                end if;
                k := k + 1;
            end loop;
        else
            raise exception 'Cannot parse Google API''s response properly (see Details to check full "response" JSON)'
                using detail = jsonb_pretty(response::jsonb);
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
    if current_setting('google_translate.api_key') is null or current_setting('google_translate.api_key') = '' then
        raise exception 'Configuration error: google_translate.api_key has not been set';
    end if;
    select into res translate
    from google_translate.translate(current_setting('google_translate.api_key')::text, source, target, ARRAY[q]);

    return res[1];
end;
$$ language plpgsql;

create or replace function google_translate.translate_array(source char(2), target char(2), q json) returns text[] as $$
declare
    res text[];
    qs text[];
    jtype text;
begin
    if current_setting('google_translate.api_key') is null or current_setting('google_translate.api_key') = '' then
        raise exception 'Configuration error: google_translate.api_key has not been set';
    end if;
    jtype := json_typeof(q)::text;

    if jtype <> 'array' then
        raise exception 'Unsupported format of JSON unput';
    end if;

    select into qs array(select * from json_array_elements_text(q));

    select into res translate
    from google_translate.translate(current_setting('google_translate.api_key')::text, source, target, qs);

    return res;
end;
$$ language plpgsql;
