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

  answer = plpy.execute( '''
    SELECT creds AS cookie FROM translation_proxy.authcache
    WHERE api_engine = 'promt' AND
      updated > ( now() - current_setting('translation_proxy.promt.login_timeout')::INTERVAL )
      AND creds IS NOT NULL AND creds <> ''
    LIMIT 1;
    ''' )
  if not not answer :
    return answer[0]['cookie']

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
  answer_code = curl.getinfo( pycurl.RESPONSE_CODE )
  if answer_code == 200 : # writing new cookie to db
    cookie = curl.getinfo( pycurl.INFO_COOKIELIST )
    plan = plpy.prepare( '''
      UPDATE translation_proxy.authcache
      SET ( creds, updated ) = ( $1, now() )
      WHERE api_engine = 'promt'
      ''', [ 'text' ] )
    plpy.execute( plan, [ cookie ] )
    curl.close()
    return cookie

  curl.close()
$$ LANGUAGE plpython2u;

-- from, to, text, profile
CREATE OR REPLACE FUNCTION translation_proxy._promt_translate(src char(2), dst char(2), qs text, profile text DEFAULT '') RETURNS text AS $$
  import pycurl
  from StringIO import StringIO
  from urllib import urlencode
  import json

  plan = plpy.prepare("SELECT current_setting('translation_proxy.promt.server_url')")
  server_url = "%s/Services/auth/rest.svc/Login" % plpy.execute(plan)[0]['current_setting']
  cookie = StringIO(
    plpy.execute("SELECT creds FROM translation_proxy.authcache WHERE api_engine = 'promt'")[0]['creds'] )
  buffer = StringIO()
  if not cookie.getvalue() :
    cookie.write()

  curl.setopt( curl.URL, server_url )
  curl.setopt( curl.WRITEDATA, buffer )
  curl.setopt( curl.COOKIEJAR, cookie )
  curl.setopt( curl.COOKIEFILE, cookie )
  curl.setopt( pycurl.HTTPHEADER, ['Accept: application/json', 'Content-Type: application/json'] )

  else
    plpy.execute
  curl.setopt( curl.POSTFIELDS,
    json.dumps(
      {'from': src, 'to': dst ,'text': qs, 'profile': profile } ))
  curl.perform()


$$ language plpython2u

-- server_url, cookie-file-name, source lang, target lang, text, translation profile
CREATE OR REPLACE FUNCTION translation_proxy._promt_translate_curl(char(2), char(2), text, text DEFAULT '') RETURNS text AS $$
#!/bin/sh
SERVER_URL=$1
COOKIE=$2
SRC=$3
DST=$4
QUERY=$5
PROFILE=$6
curl --connect-timeout 2 -b "$COOKIE" -c "$COOKIE" \
  -G --data-urlencode "text=$QUERY" \
	 --data-urlencode "from=$SRC" \
	 --data-urlencode "to=$DST" \
	 --data-urlencode "profile=$PROFILE" \
  "$SERVER_URL/Services/v1/rest.svc/TranslateText" 2>>/dev/null
$$ language plsh;

-- server_url, cookie-file-name, text
CREATE OR REPLACE FUNCTION translation_proxy.promt_detext_text_language(text, text, text) returns char(2) as $$
#!/bin/sh
SERVER_URL=$1
COOKIE=$2
QUERY=$3
curl --connect-timeout 2 -b "$COOKIE" -c "$COOKIE" \
  "$SERVER_URL/Services/v1/rest.svc/DetectTextLanguage?text=$QUERY" 2>/dev/null
$$ language plsh;

CREATE OR REPLACE FUNCTION translation_proxy.promt_translate(src char(2), dst char(2), qs text, profile text DEFAULT '') RETURNS text AS $$
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

  -- checking that last usage is older then timeout, do I need to login?
  SELECT id INTO last_req FROM translation_proxy.cache
    WHERE api_engine = 'promt' AND created > ( now() - current_setting('translation_proxy.promt.login_timeout')::INTERVAL )
    LIMIT 1;
  IF last_req IS NULL THEN
    RAISE DEBUG 'Authenticating to promt server ';
    SELECT INTO login_ok translation_proxy._promt_login_curl(
      current_setting('translation_proxy.promt.server_url'),
      current_setting('translation_proxy.promt.cookie_file'),
      current_setting('translation_proxy.promt.login'),
      current_setting('translation_proxy.promt.password') );
    IF login_ok != 0 THEN
  		RAISE EXCEPTION 'Server % returned authentication error', current_setting('translation_proxy.promt.server_url');
  	END IF;
  END IF;
  -- translation
  answer := translation_proxy._promt_translate_curl(
    current_setting('translation_proxy.promt.server_url'),
    current_setting('translation_proxy.promt.cookie_file'),
    src, dst, qs, profile );
  IF answer IS NULL OR answer = '' THEN
    raise exception 'Promt server responded with empty answer';
  END IF;

  INSERT INTO translation_proxy.cache ( source, target, q, result, created, api_engine )
    VALUES ( src, dst, qs, answer, now(), 'promt' );
  RETURN answer;
END;
$$ LANGUAGE plpgsql;

-- server-url, cookie-file-name
CREATE OR REPLACE FUNCTION translation_proxy._promt_logout() RETURNS BOOLEAN AS $$
  import pycurl
  from StringIO import StringIO

  plan = plpy.prepare("SELECT current_setting('translation_proxy.promt.server_url')")
  server_url = "%s/Services/auth/rest.svc/Logout" % plpy.execute(plan)[0]['current_setting']

  buffer = StringIO()
  cookie = StringIO(
    plpy.execute( "SELECT creds FROM translation_proxy.authcache WHERE api_engine = 'promt'" )[0]['creds'] )
  if cookie.len == 0 :
    return False

  curl = pycurl.Curl()
  curl.setopt( curl.URL, server_url )
  curl.setopt( curl.WRITEDATA, buffer )
  curl.setopt( curl.COOKIEFILE, cookie )
  curl.perform()
  answer_code = curl.getinfo( pycurl.RESPONSE_CODE )
  print "Возврат из HTTP %d\n" % answer_code
  if answer_code == 200 :
    plan = plpy.execute( """
      UPDATE translation_proxy.authcache
      SET ( creds, updated ) = ( NULL, now() )
      WHERE api_engine = 'promt'
    """ )
  curl.close()
  return answer_code == 200
$$ LANGUAGE plpython2u;
