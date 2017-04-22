-- Promt API
ALTER DATABASE DBNAME SET translation_proxy.promt.login = 'YOUR_PROMT_LOGIN';
ALTER DATABASE DBNAME SET translation_proxy.promt.password = 'YOUR_PROMT_PASSWORD';
ALTER DATABASE DBNAME SET translation_proxy.promt.server_url = 'YOUR_PROMT_SERVER_URL';
ALTER DATABASE DBNAME SET translation_proxy.promt.login_timeout = 'PROMT_LOGIN_TIMEOUT';
ALTER DATABASE DBNAME SET translation_proxy.promt.cookie_file = 'PROMT_COOKIE_FILE';

-- Dumb functions for login, logout, translate and detect lnaguage
-- authorizes on Promt API, writes cookie to db and returns it (or NULL) for next queries
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

-- from, to, text, profile
CREATE OR REPLACE FUNCTION translation_proxy._promt_get_translation(src char(2), dst char(2), qs text, profile text DEFAULT '')
RETURNS text AS $$
  import pycurl
  from StringIO import StringIO
  from urllib import urlencode
  import json
  import re

  plan = plpy.prepare("SELECT current_setting('translation_proxy.promt.server_url')")
  server_url = "%s/Services/v1/rest.svc/TranslateText" % plpy.execute(plan)[0]['current_setting']
  cookie = plpy.execute("SELECT translation_proxy._promt_login()")[0]['_promt_login']
  plpy.debug( "Queriyng server %s for translation" % server_url )
  buffer = StringIO()
  curl = pycurl.Curl()
  curl.setopt( pycurl.URL, server_url + '?' + urlencode({'from': src, 'to': dst ,'text': qs, 'profile': profile } ))
  curl.setopt( pycurl.WRITEDATA, buffer )
  curl.setopt( pycurl.COOKIELIST, cookie )
  curl.setopt( pycurl.VERBOSE, 1 )
  curl.perform()
  answer_code = curl.getinfo( pycurl.RESPONSE_CODE )
  curl.close()
  if answer_code != 200 :
    plpy.error( "Promt API returned %s\nBody is: %s" % ( answer_code, buffer.getvalue() ))

  # checking if there no logical error, like "translation pair does not exist"
  # normally this must return plain text
  plpy.debug('Code 200, checking for json returned')
  try:
    data = json.load(buffer)
    plpy.error( data['Message'] if ('Message' in data) else data[ data.keys()[0] ] )
  except ValueError:
    # translation is valid
    # and yes, promt answers with quoted string like '"some text"'
    return re.sub( r'^"|"$', '', buffer.getvalue() )
$$ language plpython2u;

-- from, to, text, profile
CREATE OR REPLACE FUNCTION translation_proxy.promt_translate(src char(2), dst char(2), qs text, profile text DEFAULT '')
RETURNS text AS $$
DECLARE
  last_req TEXT;
  answer TEXT;
  login_ok INTEGER;
BEGIN
  IF src = dst THEN
    RAISE EXCEPTION '''source'' cannot be equal to ''target'' (see details)'
      USING detail = 'Received equal ''source'' and ''target'': ' || source;
  END IF;

  -- checking cache
  SELECT result INTO answer
    FROM translation_proxy.cache
    WHERE api_engine = 'promt' AND source = src AND target = dst AND q = qs
    LIMIT 1;
  IF answer IS NOT NULL THEN
    RETURN answer;
  END IF;

  -- translation
  answer := translation_proxy._promt_get_translation( src, dst, qs, profile );
  IF answer IS NULL OR answer = '' THEN
    raise exception 'Promt server responded with empty answer';
  END IF;

  INSERT INTO translation_proxy.cache ( source, target, q, result, created, api_engine, profile )
    VALUES ( src, dst, qs, answer, now(), 'promt', profile );
  RETURN answer;
END;
$$ LANGUAGE plpgsql;

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
  lng := translation_proxy._load_detected_language(qs, 'promt');
  IF lng IS NOT NULL THEN
    RETURN lng;
  END IF;
  lng := translation_proxy._promt_detect_language(qs);
  IF lng <> '' THEN
    INSERT INTO translation_proxy.detection_cache
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
