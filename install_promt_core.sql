-- Main function is the promt_translate( source, destination, query[], profile )
/* Overview:
  0. insert received text to cache table where result is NULL
  1. call promt_get_translation, that loads those using CURSOR
     and add untranslated text to url until it exceeds 2000 limit
     and then translates them on Promt server
  2. for (possible) multitasking it locks records with SELECT FOR UPDATE
*/

-- Dumb functions for login, logout, translate and detect lnaguage
-- authorizes on Promt API, writes cookie to db and returns it (or NULL) for next queries
-- curl -X POST -d 'username=startupturbo' -d 'password=Startupturb0' -d 'isPersistent=false' https://nombox.csd.promt.ru/pts/Services/auth/rest.svc/Login
CREATE OR REPLACE FUNCTION translation_proxy._promt_login() RETURNS TEXT AS $$
  import pycurl
  from StringIO import StringIO
  from urllib import urlencode
  import json

  cookie = plpy.execute("SELECT translation_proxy._load_cookie('promt')")[0]['_load_cookie'];
  if not not cookie :
    plpy.debug("Found valid cookie")
    return cookie

  plpy.debug("Posting auth query to Promt API")
  plan = plpy.prepare("SELECT current_setting('translation_proxy.promt.server_url')")
  server_url = "%s/Services/auth/rest.svc/Login" % plpy.execute(plan)[0]['current_setting']
  promt_login = plpy.execute("SELECT current_setting('translation_proxy.promt.login')")[0]['current_setting']
  promt_password = plpy.execute("SELECT current_setting('translation_proxy.promt.password')")[0]['current_setting']

  buffer = StringIO()
  curl = pycurl.Curl()
  curl.setopt( curl.URL, server_url )
  curl.setopt( pycurl.HTTPHEADER, ['Accept: application/json', 'Content-Type: application/json'] )
  curl.setopt( pycurl.POST, 1 )
  curl.setopt( pycurl.POSTFIELDS,
    json.dumps(
      {'username': promt_login, 'password': promt_password ,'isPersistent': False } ))
  curl.setopt( pycurl.WRITEDATA, buffer )
  curl.setopt( pycurl.COOKIELIST, '' )
  curl.perform()
  cookie = curl.getinfo( pycurl.INFO_COOKIELIST )[0]
  plan = plpy.prepare("SELECT translation_proxy._save_cookie('promt', $1)", [ 'text' ])
  plpy.execute(plan, [ cookie ] )
  answer_code = curl.getinfo( pycurl.RESPONSE_CODE )
  curl.close()
  if answer_code == 200 : # writing new cookie to db
    return cookie

  plpy.fatal("Can't login into Promt API")
$$ LANGUAGE plpython2u;

-- initiate translation of all fields where result is NULL
CREATE OR REPLACE FUNCTION translation_proxy._promt_start_translation()
RETURNS VOID AS $$
  import pycurl
  from StringIO import StringIO
  from urllib import urlencode
  import json
  import re

  update_plan = plpy.prepare(
      "UPDATE translation_proxy.cache SET result = $1, encoded = NULL WHERE id = $2",
      [ 'text', 'bigint' ] )
  cookie = plpy.execute( "SELECT translation_proxy._promt_login()" )[0]['_promt_login']
  server_url = plpy.execute( "SELECT current_setting('translation_proxy.promt.server_url')" )[0]['current_setting'] + '/Services/v1/rest.svc/TranslateText?'

  curl = pycurl.Curl()
  curl.setopt( pycurl.HTTPHEADER, [ 'Accept: application/json' ] )
  curl.setopt( pycurl.COOKIELIST, cookie )
  cursor = plpy.cursor( """
    SELECT id, source, target, q, profile
      FROM translation_proxy.cache
      WHERE api_engine = 'promt' AND result IS NULL
      ORDER BY source, target, profile
      FOR UPDATE SKIP LOCKED
    """ )

  while True:
    row = cursor.fetch(1)
    if not row:
      break
    buffer = StringIO()
    curl.setopt( pycurl.WRITEDATA, buffer )
    curl.setopt( pycurl.URL, server_url +
        urlencode({ 'from': row[0]['source'],
          'to': row[0]['target'],
          'text': row[0]['q'],
          'profile': row[0]['profile'] }) )
    curl.perform()
    answer_code = curl.getinfo( pycurl.RESPONSE_CODE )
    if answer_code != 200 :
      plpy.error( "Promt API returned %s\nBody is: %s" % ( answer_code, buffer.getvalue() ))
    # normally this must return plain text
    # translation is valid
    # and yes, promt answers with quoted string like '"some text"'
    t = re.sub( r'^"|"$', '', buffer.getvalue() )
    plpy.debug( "Promt answer is %s", t )
    plpy.execute( update_plan, [ t, row[0]['id'] ])
    buffer.close()

  curl.close()
  buffer.close()
$$ language plpython2u;

-- from, to, text[], profile
CREATE OR REPLACE FUNCTION translation_proxy.promt_translate_array(
    src CHAR(2), dst CHAR(2), qs TEXT[], api_profile TEXT DEFAULT '')
RETURNS TEXT[] AS $BODY$
DECLARE
  new_row_ids BIGINT[]; -- saving here rows that needs translation
  r TEXT[];
BEGIN
  SET SCHEMA 'translation_proxy';
  IF src = dst THEN
    RAISE EXCEPTION '''source'' cannot be equal to ''target'' (see details)'
      USING detail = 'Received equal ''source'' and ''target'': ' || source;
  END IF;
  IF array_length(qs, 1) = 0 THEN
    RAISE EXCEPTION 'NEED SOMETHING TO TRANSLATE';
  END IF;
  -- let Promt translates rows with NULL result
  WITH created( saved_ids ) AS (
    INSERT INTO cache ( source, target, q, profile, api_engine )
      ( SELECT src, dst, unnest(qs), api_profile, 'promt' )
      ON CONFLICT (md5(q), source, target, api_engine, profile) DO
        UPDATE SET source = src
          -- this is dirty hack doing nothing with table only for returning all requested ids
      RETURNING id )
    SELECT array_agg( saved_ids ) FROM created INTO new_row_ids;
  IF ( current_setting('translation_proxy.promt.valid_from') IS NOT NULL
          AND current_setting('translation_proxy.promt.valid_from')::timestamp < current_timestamp )
        AND ( current_setting('translation_proxy.promt.valid_until') IS NOT NULL
          AND current_setting('translation_proxy.promt.valid_until')::timestamp > current_timestamp )
        AND array_length( new_row_ids, 1 ) > 0 THEN
    PERFORM _promt_start_translation();
  END IF;
  -- all translations are in the cache table now
  SELECT array_agg( result ) FROM cache WHERE id IN ( SELECT unnest( new_row_ids ) ) INTO r;
  RETURN r;
END;
$BODY$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION translation_proxy.promt_translate(
    src CHAR(2), dst CHAR(2), qs TEXT, api_profile text DEFAULT '') RETURNS TEXT[] AS $BODY$
BEGIN
  SELECT translation_proxy.promt_translate_array( src, dst, ARRAY[qs], api_profile);
END;
$BODY$ LANGUAGE plpgsql;

-- text, returns language, saves to cache
CREATE OR REPLACE FUNCTION translation_proxy._promt_detect_language(qs text)
RETURNS CHAR(10) AS $$
  import pycurl
  from StringIO import StringIO
  from urllib import urlencode

  plan = plpy.prepare("SELECT current_setting('translation_proxy.promt.server_url')")
  server_url = "%s/Services/v1/rest.svc/DetectTextLanguage" % plpy.execute(plan)[0]['current_setting']
  cookie = plpy.execute("SELECT translation_proxy._promt_login()")[0]['_promt_login']

  buffer = StringIO()
  curl = pycurl.Curl()
  curl.setopt( pycurl.URL, server_url + '?' + urlencode({ 'text': qs } ))
  curl.setopt( pycurl.WRITEDATA, buffer )
  curl.setopt( pycurl.COOKIELIST, cookie )
  curl.perform()
  answer_code = curl.getinfo( pycurl.RESPONSE_CODE )
  curl.close()
  if answer_code != 200 :
    plpy.error( "Promt API returned %s\nBody is: %s" % ( answer_code, buffer.getvalue() ))
  answer = buffer.getvalue().decode('utf-8').replace('"','')
  buffer.close()
  plpy.debug("Answer len is %d, content is %s, unicode? %d" % ( len(answer), answer, isinstance(answer, unicode) ) )

  if answer != 'kk':
    return answer

  plpy.error("Promt don't know that language" )
$$ language plpython2u;

CREATE OR REPLACE FUNCTION translation_proxy.promt_detect_language(qs text)
RETURNS char(2) as $$
DECLARE
  lng TEXT;
BEGIN
  IF qs = '' OR qs IS NULL THEN
    RAISE EXCEPTION 'text cannot be equal empty';
  END IF;
  -- checking cache
  lng := translation_proxy._find_detected_language(qs, 'promt');
  IF lng IS NOT NULL THEN
    RETURN lng;
  END IF;
  lng := translation_proxy._promt_detect_language(qs);
  IF lng <> '' THEN
    INSERT INTO translation_proxy.cache
        ( lang, q, api_engine ) VALUES ( lng, qs, 'promt' );
  END IF;
  RETURN lng;
END;
$$ LANGUAGE plpgsql;

-- server-url, cookie-file-name
CREATE OR REPLACE FUNCTION translation_proxy._promt_logout() RETURNS BOOLEAN AS $$
  import pycurl
  from StringIO import StringIO

  plan = plpy.prepare("SELECT current_setting('translation_proxy.promt.server_url')")
  server_url = "%s/Services/auth/rest.svc/Logout" % plpy.execute(plan)[0]['current_setting']

  buffer = StringIO()
  cookie = plpy.execute( "SELECT creds FROM translation_proxy.authcache WHERE api_engine = 'promt'" )[0]['creds']
  if not cookie :
    return False

  curl = pycurl.Curl()
  curl.setopt( pycurl.URL, server_url )
  curl.setopt( pycurl.WRITEDATA, buffer )
  curl.setopt( pycurl.COOKIELIST, cookie )
  curl.perform()
  answer_code = curl.getinfo( pycurl.RESPONSE_CODE )
  if answer_code == 200 :
    plan = plpy.execute( """
      UPDATE translation_proxy.authcache
      SET ( creds, updated ) = ( NULL, now() )
      WHERE api_engine = 'promt'
    """ )
  curl.close()
  return answer_code == 200
$$ LANGUAGE plpython2u;
