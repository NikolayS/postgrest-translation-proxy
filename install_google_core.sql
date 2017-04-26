-- Google API
alter database DBNAME set translation_proxy.google.api_key = 'YOUR_GOOGLE_API_KEY';
alter database DBNAME set translation_proxy.google.begin_at = 'GOOGLE_BEGIN_AT';
alter database DBNAME set translation_proxy.google.end_at = 'GOOGLE_END_AT';

-- fetches translations, listed in URL and saves them into cache
-- stores current request into local session cache (SD) and calls API only on overflow
-- must be called once more after the loop with id = nil to (possibly) flush the cache
CREATE OR REPLACE FUNCTION translation_proxy._google_fetch_translations( id BIGINT, source TEXT, target TEXT, q TEXT )
RETURNS VOID AS $BODY$
  import pycurl
  from StringIO import StringIO
  from urllib import quote_plus
  import json
  import re

  if id and target and q:
    if not SD['data']:
      plpy.debug('Promt: init SD')
      SD['url'] = SD['url'] = 'https://www.googleapis.com/language/translate/v2?key=' +
        plpy.execute("current_setting('translation_proxy.google.api_key')")[0]['current_setting'] +
        '&target=' + target + '&source=' + onerec.source
      SD['data'] = []

    SD['url'] += '&text=' + quote_plus (q)
    SD['data'].append( [{ 'id': id, 'source': source, 'target': target, 'q': q }] )

    if len( SD['url'] ) < 1980 and SD['data'][0]['source'] == source and SD['data'][0]['target'] == target:
      return None;

  if SD['data'] and SD['url']:
    plpy.debug('Fetching google, url is %s' % SD['url'])
    buffer = StringIO()
    curl = pycurl.Curl()
    curl.setopt( pycurl.WRITEDATA, buffer )
    curl.setopt( pycurl.HTTPHEADER, [ 'Accept: application/json' ] )
    curl.setopt( pycurl.URL, SD['url'] )
    curl.perform()
    answer_code = curl.getinfo( pycurl.RESPONSE_CODE )
    if answer_code != 200 :
      plpy.error( "Google returned %d", answer_code )
    try:
      answer = json.loads( buffer.getvalue() )
    except ValueError:
      buffer.close()
      curl.close()
      plpy.error("Google was returned just a plain text. Maybe this is an error.", detail = buffer.getvalue() )

    buffer.close()
    curl.close()
    i = 0
    update_plan = plpy.prepare( "UPDATE translation_proxy.cache SET result = $1, encoded = NULL WHERE id = $2",
        [ 'TEXT', 'BIGINT' ] )
    for x in answer['data']['translations'] :
      plpy.debug("Google translated for id №%d : '%s'", ( SD['data'][i]['id'], x['translatedText'] ))
      t = re.sub( r'^"|"$', '', x['translatedText'] )
      plpy.execute( update_plan, [ t, SD['data'][i]['id'] ] )
      i += 1

    plpy.debug('Clearing SD')
    SD['url'] = ''
    SD['data'] = []

    return None
$BODY$ LANGUAGE plpython2u;

-- initiate translation of all fields where result is NULL
CREATE OR REPLACE FUNCTION translation_proxy._google_start_translation()
RETURNS VOID AS $$
DECLARE
  onerec RECORD;
  url_base TEXT DEFAULT '';
  src TEXT DEFAULT '';
  dst TEXT DEFAULT '';
  prf TEXT DEFAULT '';
  current_ids BIGINT[] DEFAULT ARRAY[]::BIGINT[]; -- ids, currently added to url
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
        RAISE DEBUG 'Parameters was changed, escaping. source is %, target is %', onerec.source, onerec.target;
        src = onerec.source; dst = onerec.target; prf = onerec.profile;
        RAISE EXCEPTION USING
          errcode = 'EOURL',
          message = 'Parameters are changed, time to fetch ' || onerec.id;
      END IF;
      RAISE DEBUG 'Adding more requests to url, №%', onerec.id;
      url_base := translation_proxy._urladd( (url_base || '&q='), onerec.q );
      current_ids := array_append( current_ids, onerec.id );
      RAISE DEBUG 'Added id %, and continuing with url %', onerec.id, url_base;
    EXCEPTION
      WHEN sqlstate 'EOURL' THEN
        RAISE DEBUG 'EOURL on №%', onerec.id;
        IF url_base <> '' THEN
          PERFORM translation_proxy._google_fetch_translations( url_base, current_ids );
        END IF;
        -- pushing the last request back to the url
        RAISE DEBUG 'pushing the last request back to the url';
        current_ids := ARRAY[ onerec.id ];
        SELECT 'https://www.googleapis.com/language/translate/v2?key=' ||
                    current_setting('translation_proxy.google.api_key') ||
                    '&target=' || onerec.target ||
                    '&source=' || onerec.source ||
                    '&q=' || translation_proxy._urlencode( onerec.q ) INTO url_base;
        -- here it will translate even long string, one-by-one.
        RAISE DEBUG 'Inside exception, url_base == %', url_base;
    END;
  END LOOP;
  RETURN;
END;
$$ LANGUAGE plpgsql VOLATILE;

-- main function, saves all requests to cache and initiates start_translation
CREATE OR REPLACE FUNCTION translation_proxy.google_translate(
  src CHAR(2), dst CHAR(2), qs TEXT[], api_profile TEXT DEFAULT '')
RETURNS TEXT[] AS $$
DECLARE
    new_row_ids BIGINT[]; -- saving here rows that needs translation
    can_remote BOOLEAN DEFAULT 'f';
    r TEXT[];
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
  -- let google translates rows with NULL result
  WITH created( saved_ids ) AS (
    INSERT INTO translation_proxy.cache ( source, target, q, profile, api_engine )
      ( SELECT src, dst, unnest(qs), api_profile, 'google' )
      ON CONFLICT (md5(q), source, target, api_engine, profile) DO
        UPDATE SET source = src
          -- this is dirty hack doing nothing with table only for returning all requested ids
    RETURNING id )
    SELECT array_agg( saved_ids ) FROM created INTO new_row_ids;
  IF ( current_setting('translation_proxy.google.begin_at') IS NOT NULL
          AND current_setting('translation_proxy.google.begin_at')::timestamp < current_timestamp )
        AND ( current_setting('translation_proxy.google.end_at') IS NOT NULL
          AND current_setting('translation_proxy.google.end_at')::timestamp > current_timestamp )
        AND array_length( new_row_ids, 1 ) > 0 THEN
    PERFORM _google_start_translation();
  END IF;
  -- all translations are in the cache table now
  SELECT array_agg( result ) FROM cache WHERE id IN ( SELECT unnest( new_row_ids ) ) INTO r;
  RETURN r;
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
