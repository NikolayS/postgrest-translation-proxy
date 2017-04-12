-- Promt API
ALTER DATABASE DBNAME SET translation_proxy.promt.login = 'YOUR_PROMT_LOGIN';
ALTER DATABASE DBNAME SET translation_proxy.promt.password = 'YOUR_PROMT_PASSWORD';
ALTER DATABASE DBNAME SET translation_proxy.promt.server_url = 'YOUR_PROMT_SERVER_URL';
ALTER DATABASE DBNAME SET translation_proxy.promt.login_timeout = 'PROMT_LOGIN_TIMEOUT';
ALTER DATABASE DBNAME SET translation_proxy.promt.cookie_file = 'PROMT_COOKIE_FILE';

-- Dumb functions for login, logout, translate and detect lnaguage
-- server-url, cookie-file, login, password; returns 0 if no errors
CREATE OR REPLACE FUNCTION translation_proxy._promt_login_curl(text, text, text, text) RETURNS TEXT AS $$
#!/bin/sh
SERVER_URL=$1
AUTH="$SERVER_URL/Services/auth/rest.svc/Login"
COOKIE=$2
LOGIN=$3
PASSWORD=$4
curl --connect-timeout 2 -c "$COOKIE" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  --data-urlencode "{\"username\":\"$LOGIN\",\"password\":\"$PASSWORD\",\"isPersistent\":\"false\"}" "$AUTH" 2>/dev/null | grep 'true'
$$ language plsh;

-- server-url, cookie-file-name
CREATE OR REPLACE FUNCTION translation_proxy._promt_logout_curl(text, text) RETURNS TEXT AS $$
#!/bin/sh
SERVER_URL=$1
AUTH="$SERVER_URL/Services/auth/rest.svc/Logout"
COOKIE=$2
curl --connect-timeout 2 -b "$COOKIE" -c "$COOKIE" "$AUTH" 2>/dev/null
$$ language plsh;

-- server_url, cookie-file-name, source lang, target lang, text, translation profile
CREATE OR REPLACE FUNCTION translation_proxy._promt_translate_curl(text, text, char(2), char(2), text, text DEFAULT '') RETURNS text AS $$
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
  "$SERVER_URL/Services/v1/rest.svc/TranslateText" 2>/dev/null
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
BEGIN
  -- checking cache
  SELECT result INTO answer
	FROM cache
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
    PERFORM translation_proxy._promt_login_curl(
      current_setting('translation_proxy.promt.server_url'),
      current_setting('translation_proxy.promt.cookie_file'),
      current_setting('translation_proxy.promt.login'),
      current_setting('translation_proxy.promt.password') );
  END IF;
  -- translation
  answer := translation_proxy._promt_translate_curl(
    current_setting('translation_proxy.promt.server_url'),
    current_setting('translation_proxy.promt.cookie_file'),
    src, dst, qs, profile );
  INSERT INTO translation_proxy.cache ( source, target, q, result, created, api_engine )
    VALUES ( src, dst, qs, answer, now(), 'promt' );
  RETURN answer;
END;
$$ LANGUAGE plpgsql;
