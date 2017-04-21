-- Google API
alter database DBNAME set translation_proxy.google.api_key = 'YOUR_GOOGLE_API_KEY';
alter database DBNAME set translation_proxy.google.begin_at = 'GOOGLE_BEGIN_AT';
alter database DBNAME set translation_proxy.google.end_at = 'GOOGLE_END_AT';

create or replace function translation_proxy.urlencode(text) returns text as $$
    select
        string_agg(
            case
                when ascii(ch) in (32, 160) then -- spaces, CR, LF
                    '+'
                when ascii(ch) between 127 and 165 then -- unsupported chars
                    '+'
                when ol=1 and (ch ~ '[+\]\[%&#]+' or ascii(ch) < 32)  -- this is not traditional urlencode!
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

-- api_key, source lang, target lang, text
create or replace function translation_proxy._google_translate_curl(text, char(2), char(2), text) returns text as $$
#!/bin/sh
curl --connect-timeout 2 -H "Accept: application/json" "https://www.googleapis.com/language/translate/v2?key=$1&source=$2&target=$3&q=$4" 2>/dev/null | sed 's/\r//g'
$$ language plsh;

CREATE OR REPLACE FUNCTION translation_proxy.google_translate(src char(2), dst char(2), qs text[]) RETURNS TEXT[] AS $$
  import pycurl
  from StringIO import StringIO
  from urllib import urlencode
  import json

  if src == dst :
    plpy.error("Destination language must be other than source one.")
  if not qs
    plpy.error("Not enough text for translation.")

  api_key = plpy.execute("SELECT translation_proxy._load_cookie('google')")[0]['_load_cookie']
  buffer = StringIO()
  curl = pycurl.Curl()
  curl.setopt( pycurl.URL,
    'https://www.googleapis.com/language/translate/v2?' +
    urlencode({ 'key': api_key, 'source': src, 'target': dst ,'q': qs } ))
  curl.setopt( pycurl.WRITEDATA, buffer )
  curl.setopt( pycurl.HTTPHEADER, [ 'Accept: application/json' ] )
  curl.setopt( pycurl.VERBOSE, 1 )
  curl.perform()
  answer_code = curl.getinfo( pycurl.RESPONSE_CODE )
  curl.close()
  if answer_code != 200 :
    plpy.error( "Google returned %d", answer_code )


$$ LANGUAGE plpgsql;

create or replace function translation_proxy.google_translate(api_key text, source char(2), target char(2), qs text[]) returns text[] as $$
declare
    qs2call text[];
    i2call int4[];
    q2call_urlencoded text;
    url_len int4;
    response json;
    response_text text;
    resp_1 json;
    res text[];
    k int4;
    rec record;
begin
    res := qs; -- by default, return input "as is"
    qs2call := array[]::text[];
    i2call := array[]::int4[];
    q2call_urlencoded := '';

    if source = target then
        raise exception '''source'' cannot be equal to ''target'' (see details)'
            using detail = 'Received equal ''source'' and ''target'': '
                || source || ', qs: [' || array_to_string(qs, ';') || ']';
    end if;

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
            translation_proxy.cache
        right join queries on md5(trim(queries.q)) = md5(cache.q)
            and cache.source = google_translate.source
            and cache.target = google_translate.target
    loop
        raise debug 'INPUT: i: %, q: "%", result found in cache: "%"', rec.i, rec.q, rec.result;
        if rec.result is not null then
            res[rec.i] := rec.result;
        elsif (current_setting('translation_proxy.google.begin_at') is not null
                            and current_setting('translation_proxy.google.begin_at')::timestamp > current_timestamp
              ) or (current_setting('translation_proxy.google.end_at') is not null
                            and current_setting('translation_proxy.google.end_at')::timestamp < current_timestamp
              ) then
            res[rec.i] := rec.q;
        else
            qs2call = array_append(qs2call, trim(rec.q));
            i2call = array_append(i2call, rec.i);
            if q2call_urlencoded <> '' then
                q2call_urlencoded := q2call_urlencoded || '&q=';
            end if;
            q2call_urlencoded := q2call_urlencoded || replace(translation_proxy.urlencode(trim(rec.q)), ' ', '+');
        end if;
    end loop;
    raise debug 'TO PASS TO GOOGLE API: qs2call: %, i2call: %', array_to_string(qs2call, '*'), array_to_string(i2call, '-');
    raise debug 'URLENCODED STRING: %', q2call_urlencoded;

    if q2call_urlencoded <> '' then
        url_len := length(q2call_urlencoded);
        raise debug 'q2call_urlencoded length=%, total URL length=%', url_len, (url_len + 115);
        if url_len > 1885 then
            raise exception 'Google API''s character limit (2K) is exceeded, total URL length=%', (url_len + 115);
        end if;
        raise info 'Calling Google Translate API for source=%, target=%, q=%', source, target, q2call_urlencoded;
        begin
          select into response_text translation_proxy._google_translate_curl(api_key, source, target, q2call_urlencoded);
          response := response_text::json;
        exception
          when invalid_text_representation then -- Google returned text, not JSON
            raise exception 'Google Translate API returned text, not JSON (see details)'
              using detail = response_text,
              hint = 'Google Translate API usually returns text instead of JSON if something is wrong with the request (error 400 "Bad Request").';
        end;
        if response is null then
            raise exception 'Google API responded with empty JSON';
        elsif response->'error'->'message' is not null then
            raise exception 'Google API responded with error (query: source=%, target=%): %'
                , source, target, response->'error'->'message'::text
                using detail = jsonb_pretty((response->'error'->'errors')::jsonb);
        elsif response->'data'->'translations'->0->'translatedText' is not null then
            k := 1;
            for resp_1 in select * from json_array_elements(response->'data'->'translations')
            loop
                res[i2call[k]] := regexp_replace((resp_1->'translatedText')::text, '"$|^"', '', 'g');
                if res[i2call[k]] <> '' then
                    insert into translation_proxy.cache(source, target, q, result, api_engine)
                    values(google_translate.source, google_translate.target, qs2call[k], res[i2call[k]], 'google')
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

create or replace function translation_proxy.google_translate(source char(2), target char(2), qs text[]) returns text[] as $$
begin
    if current_setting('translation_proxy.google.api_key') is null or current_setting('translation_proxy.google.api_key') = '' then
        raise exception 'Configuration error: translation_proxy.google.api_key has not been set';
    end if;

    return translation_proxy.google_translate(current_setting('translation_proxy.google.api_key')::text, source, target, qs);
end;
$$ language plpgsql;

create or replace function translation_proxy.google_translate(source char(2), target char(2), q text) returns text as $$
declare
    res text[];
begin
    if current_setting('translation_proxy.google.api_key') is null or current_setting('translation_proxy.google.api_key') = '' then
        raise exception 'Configuration error: translation_proxy.google.api_key has not been set';
    end if;
    select into res google_translate
    from translation_proxy.google_translate(current_setting('translation_proxy.google.api_key')::text, source, target, ARRAY[q]);

    return res[1];
end;
$$ language plpgsql;

create or replace function translation_proxy.google_translate_array(source char(2), target char(2), q json) returns text[] as $$
declare
    res text[];
    qs text[];
    jtype text;
begin
    if current_setting('translation_proxy.google.api_key') is null or current_setting('translation_proxy.google.api_key') = '' then
        raise exception 'Configuration error: translation_proxy.google.api_key has not been set';
    end if;
    jtype := json_typeof(q)::text;

    if jtype <> 'array' then
        raise exception 'Unsupported format of JSON unput';
    end if;

    select into qs array(select * from json_array_elements_text(q));

    select into res google_translate
    from translation_proxy.google_translate(current_setting('translation_proxy.google.api_key')::text, source, target, qs);

    return res;
end;
$$ language plpgsql;
