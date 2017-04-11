-- Promt API
ALTER DATABASE DBNAME SET translation_proxy.promt_login = 'YOUR_PROMT_LOGIN';
ALTER DATABASE DBNAME SET translation_proxy.promt_password = 'YOUR_PROMT_PASSWORD';
ALTER DATABASE DBNAME SET translation_proxy.promt_server_url = 'YOUR_PROMT_SERVER_URL';
ALTER DATABASE DBNAME SET translation_proxy.promt_login_timeout = 'PROMT_LOGIN_TIMEOUT';

-- Dumb functions for login, logout, translate and detect lnaguage
-- server-url, login, password; returns cookie-file-name
CREATE OR REPLACE FUNCTION translation_proxy._promt_login_curl(text, text, text) RETURNS TEXT AS $$
#!/bin/sh
SERVER_URL=$1
AUTH="$SERVER_URL/Services/auth/rest.svc/Login"
COOKIE=$( mktemp "/tmp/promt.XXXXX.jar" )
curl --connect-timeout 2 -c "$COOKIE" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$2\",\"password\":\"$3\",\"isPersistent\":\"false\"}" "$AUTH" 2>/dev/null | grep 'true'
echo -n "$COOKIE"
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
curl --connect-timeout 2 -b "$COOKIE" -c "$COOKIE" \
  "$SERVER_URL/Services/v1/rest.svc/TranslateText?text=$5&from=$3&to=$4&profile=$6" 2>/dev/null
$$ language plsh;

-- server_url, cookie-file-name, text
CREATE OR REPLACE FUNCTION translation_proxy.promt_detext_text_language(text, text, text) returns char(2) as $$
#!/bin/sh
SERVER_URL=$1
COOKIE=$2
curl --connect-timeout 2 -b "$COOKIE" -c "$COOKIE" \
  "$SERVER_URL/Services/v1/rest.svc/DetectTextLanguage?text=$4" 2>/dev/null
$$ language plsh;

CREATE OR REPLACE FUNCTION translation_proxy.promt_translate(source char(2), target char(2), qs text, profile text DEFAULT '') RETURNS text AS $$
DECLARE
  last_login INTEGER;
  answer TEXT;
BEGIN
  -- checking that last usage is more then timeout
  SELECT id INTO last_login FROM translation_proxy.cache
    WHERE api_engine = 'promt' AND created > ( now() - current_setting('translation_proxy.promt_login_timeout')::INTERVAL )
    LIMIT 1;
  IF last_login IS NULL THEN
    ALTER DATABASE DBNAME SET translation_proxy.promt_cookie_file = translation_proxy._promt_login_curl(
      current_setting('translation_proxy.promt_server_url'),
      current_setting('translation_proxy.promt_login'),
      current_setting('translation_proxy.promt_password') );
  END IF;
  -- translation
  SELECT translation_proxy._promt_translate_curl(
    current_setting('translation_proxy.promt_server_url')
  )
    INTO answer;

END;
$$ LANGUAGE plpgsql;
