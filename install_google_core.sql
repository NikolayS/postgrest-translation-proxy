-- Google API
alter database DBNAME set translation_proxy.google.api_key = 'YOUR_GOOGLE_API_KEY';
alter database DBNAME set translation_proxy.google.begin_at = 'GOOGLE_BEGIN_AT';
alter database DBNAME set translation_proxy.google.end_at = 'GOOGLE_END_AT';

-- fetches translations, listed in URL, and returns them as JSON
CREATE OR REPLACE FUNCTION translation_proxy._google_fetch_translations( url TEXT )
RETURNS JSONB AS $$
  import pycurl
  from StringIO import StringIO
  from urllib import urlencode
  import json

  api_key = plpy.execute("SELECT translation_proxy._load_cookie('google')")[0]['_load_cookie']
  buffer = StringIO()
  curl = pycurl.Curl()
  curl.setopt( pycurl.WRITEDATA, buffer )
  curl.setopt( pycurl.HTTPHEADER, [ 'Accept: application/json' ] )
  curl.setopt( pycurl.VERBOSE, 1 )
  curl.setopt( pycurl.URL, url )
  curl.perform()
  answer_code = curl.getinfo( pycurl.RESPONSE_CODE )
  if answer_code != 200 :
    plpy.error( "Google returned %d", answer_code )
  try:
    answer = json.load(buffer)
  except ValueError:
    plpy.error('Google was returned just a plain text. Maybe this is an error.')
  buffer.close()
  curl.close()
  return answer
$$ LANGUAGE plpython2u;

-- receives partial translation fetched from API and saves them into cache
CREATE OR REPLACE FUNCTION translation_proxy._google_save_translations( ids BIGSERIAL[], answer JSON )
RETURNS JSON AS $BODY$
DECLARE
  i INT4 0;
  j INT4 0;
  x BIGSERIAL;
  r RECORD;
BEGIN
--  IF answer->'data'->'translations'->0->'translatedText' IS NOT NULL THEN
-- loop over inserted IDS exactly in the same order
  FOR x IN ids LOOP
    IF ( SELECT result FROM translation_proxy.cache
            WHERE id = x AND result IS NULL ) IS NULL THEN

    IF ( SELECT result FROM translation_proxy.cache WHERE id = ids[i] ) IS NOT NULL THEN
      UPDATE translation_proxy.cache
        SET result = regexp_replace(( json_array_elements( answer->'data'->'translations'[i] ))::text, '"$|^"', '', 'g')
        WHERE id = ids[i];
    END IF;
    i := i + 1;
  END LOOP;
end if;

END;
$BODY$ LANGUAGE plpgsql;

-- initiate translation of all fields where result is NULL
CREATE OR REPLACE FUNCTION translation_proxy._google_start_translation()
RETURNS VOID AS $$
DECLARE
  onecursor refcursor;
  onerec RECORD;
  url_base TEXT;
  src TEXT;
  dst TEXT;
  prf TEXT;
BEGIN
  FOR onerec IN SELECT id, source, target, q, profile
    FROM translation_proxy.cache
    WHERE api_engine = 'google' AND result IS NULL
    ORDER BY source, target, profile
    FOR UPDATE SKIP LOCKED
  LOOP
      BEGIN
        RAISE DEBUG 'onerec.id is %', onerec.id;
        IF onerec.source <> src OR onerec.target <> dst OR onerec.profile <> prf THEN
          src = onerec.source; dst = onerec.target; prf = onerec.profile;
          RAISE EXCEPTION USING
            errcode = 'EOURL',
            message = 'Parameters are changed, time to fetch ' || onerec.id;
        END IF;
        url_base := translation_proxy._urladd( url_base + '&q=', onerec.q );
        RAISE DEBUG 'Continue with url %', url_base;
      EXCEPTION
        WHEN sqlstate 'EOURL' THEN
          RAISE DEBUG 'Overflow on №%', onerec.id;
          IF url_base <> '' THEN
            EXECUTE translation_proxy._google_parse_answer(

                translation_proxy._google_fetch_translations( url_base )
            );
          END IF;
          url_base := translation_proxy._urladd( 'https://www.googleapis.com/language/translate/v2?key=' ||
                translation_proxy._load_cookie( 'google' ) ||
                '&target=' || onerec.target ||
                '&source=' || onerec.source ||
                '&q=', onerec.q );
      END;
      RAISE DEBUG 'Still upgrading url with №%', onerec.id;
  END LOOP;
  RAISE DEBUG '--- EL';
  RETURN;
END;
$$ LANGUAGE plpgsql VOLATILE;

-- main function, saves all requests to cache and initiates start_translation
CREATE OR REPLACE FUNCTION translation_proxy.google_translate(
  src CHAR(2), dst CHAR(2), qs TEXT[], api_profile TEXT DEFAULT '')
RETURNS TEXT[] AS $$
DECLARE
    new_row_ids BIGSERIAL[]; -- saving here rows that needs translation
    can_remote BOOLEAN 'f';
BEGIN
  SET SCHEMA 'translation_proxy';
  IF src = dst THEN
      RAISE EXCEPTION '''source'' cannot be equal to ''target'' (see details)'
          USING detail = 'Received equal ''source'' and ''target'': '
              || src || ', qs: [' || array_to_string(qs, ';') || ']';
  END IF;
  IF array_length(qs, 1) = 0 THEN
    RAISE EXCEPTION 'NEED SOMETHING TO TRANSLATE';
  END IF;
  can_remote := ( current_setting('translation_proxy.google.begin_at') IS NOT NULL
                  AND current_setting('translation_proxy.google.begin_at')::timestamp < current_timestamp )
                OR ( current_setting('translation_proxy.google.end_at') IS NOT NULL
                  AND current_setting('translation_proxy.google.end_at')::timestamp > current_timestamp );
  -- let google translates rows with NULL result
  new_row_ids :=
      INSERT INTO cache (source, target, q, result, api_engine )
        SELECT src, dst, unnest(qs), api_profile, 'google'
          ON CONFLICT (md5(q), source, target, api_engine, profile) DO
            UPDATE SET source = src ON
            -- this is dirty hack doing nothing with table only for returning all requested ids
      RETURNING id;
  IF can_remote AND array_length( new_row_ids, 1 ) > 0 THEN
    EXECUTE _google_fetch_translations();
  END IF;
  -- all translations are in cache table now
  RETURN SELECT result FROM cache WHERE id IN ( new_row_ids );
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION translation_proxy.google_translate_array(source CHAR(2), target CHAR(2), q JSON)
  RETURNS TEXT[] AS $$
DECLARE
    res TEXT[];
    qs TEXT[];
    jtype TEXT;
BEGIN
    IF current_setting('translation_proxy.google.api_key') IS NULL
        OR current_setting('translation_proxy.google.api_key') = '' THEN
      RAISE EXCEPTION 'Configuration error: translation_proxy.google.api_key has not been set';
    END IF;
    jtype := json_typeof(q)::TEXT;
    IF jtype <> 'array' THEN
        RAISE EXCEPTION 'Unsupported format of JSON unput';
    END IF;
    SELECT INTO qs ARRAY(SELECT * FROM json_array_elements_text(q));
    SELECT INTO res google_translate
      FROM translation_proxy.google_translate( source, target, qs );

    RETURN res;
END;
$$ LANGUAGE plpgsql;
