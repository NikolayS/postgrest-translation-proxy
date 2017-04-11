-- Promt API
ALTER DATABASE DBNAME SET translation_proxy.promt_login = 'YOUR_PROMT_LOGIN';
ALTER DATABASE DBNAME SET translation_proxy.promt_password = 'YOUR_PROMT_PASSWORD';
ALTER DATABASE DBNAME SET translation_proxy.promt_server_url = 'YOUR_PROMT_SERVER_URL';

-- server_url, login, password, source lang, target lang, text, translation profile
CREATE OR REPLACE FUNCTION translation_proxy._promt_translate_curl(text, text, text, char(2), char(2), text, text DEFAULT '') RETURNS text AS $$
#!/bin/sh
SERVER_URL=$1
AUTH="$SERVER_URL/Services/auth/rest.svc/Login"
API="$SERVER_URL/Services/v1/rest.svc/TranslateText"
COOKIE=$( mktemp "/tmp/promt.XXXXX.jar" )
curl --connect-timeout 2 -c "$COOKIE" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$2\",\"password\":\"$3\",\"isPersistent\":\"false\"}" "$AUTH" | grep 'true'
ret=`curl --connect-timeout 2 -b "$COOKIE" -H "Accept: application/json" -H "Content-Type: application/json" \
  "$API?text=$6&from=$4&to=$5&profile=$7" 2>/dev/null`
rm "$COOKIE"
echo -n $ret
$$ language plsh;

CREATE OR REPLACE FUNCTION translation_proxy.promt_detext_text_language(text, text, text, text) returns char(2) as $$
#!/bin/sh
SERVER_URL=$1
AUTH="$SERVER_URL/Services/auth/rest.svc/Login"
API="$SERVER_URL/Services/v1/rest.svc/DetectTextLanguage"
COOKIE=$( mktemp "/tmp/promt.XXXXX.jar" )
curl --connect-timeout 2 -c "$COOKIE" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$2\",\"password\":\"$3\",\"isPersistent\":\"false\"}" "$AUTH" | grep 'true'
ret=`curl --connect-timeout 2 -b "$COOKIE" -H "Accept: application/json" -H "Content-Type: application/json" \
  "$API?text=$4" 2>/dev/null`
rm "$COOKIE"
echo -n $ret
  END;
$$ language plsh;

CREATE OR REPLACE FUNCTION translation_proxy.promt_translate(source char(2), target char(2), qs text[], profile text DEFAULT '') RETURNS text[] AS $$
BEGIN
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION translation_proxy.promt_translate(source char(2), target char(2), q text, profile text DEFAULT '') RETURNS text AS $$
DECLARE
  res text[];
BEGIN
  IF current_setting('translation_proxy.promt_login') is NULL OR current_setting('translation_proxy.promt_login') = '' THEN
    raise exception 'Configuration error: translation_proxy.promt_login has not been set';
  END IF;
  IF source = target THEN
    raise exception '''source'' cannot be equal to ''target'' (see details)'
        USING detail = 'Received equal ''source'' and ''target''';
  END IF;

  SELECT INTO res translate
    FROM translation_proxy._promt_translate_curl(
      current_setting('translation_proxy.promt_server_url')::text,
      current_setting('translation_proxy.promt_login')::text,
      current_setting('translation_proxy.promt_password')::text,
      source, target, ARRAY[q]);

    return res[1];
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION translation_proxy.promt_translate_array(source char(2), target char(2), q json) returns text[] as $$
BEGIN
END;
$$ language plpgsql;
