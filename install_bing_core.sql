-- Microsoft Bing
ALTER DATABASE DBNAME SET translation_proxy.bing.api_key = 'YOUR_BING_API_KEY';
ALTER DATABASE DBNAME SET translation_proxy.bing.key_expiration = 'BING_TOKEN_EXPIRATION';

-- main function is the bing_translate( source char(2), target char(2), qs text[] )

-- api_key
CREATE OR REPLACE FUNCTION translation_proxy._bing_get_token_curl(text) RETURNS INTEGER AS $$
#!/bin/sh
KEY=$1
ACCESS_TOKEN = `curl -X POST -H "content-type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials&client_id=$CLIENTID&client_secret=$CLIENTSECRET&scope=http://api.microsofttranslator.com" \
  https://datamarket.accesscontrol.windows.net/v2/OAuth2-13 | grep -Po '"access_token":.*?[^\\]",'`

curl -X POST --header 'Ocp-Apim-Subscription-Key: ${KEY}' --data "" 'https://api.cognitive.microsoft.com/sts/v1.0/issueToken' 2>/dev/null
$$ LANGUAGE plsh;

CREATE OR REPLACE FUNCTION translation_proxy._bing_login() RETURNS BOOLEAN AS $$
DECLARE
  token TEXT;
BEGIN
  token := translation_proxy._bing_get_token_curl(current_setting('translation_proxy.bing.api_key'));
  IF token IS NOT NULL AND token <> '' THEN
    UPDATE translation_proxy.authcache SET ( creds, updated ) = ( token, now() ) WHERE api_engine = 'bing';
    RETURN 't';
  ELSE
    RETURN 'f';
  END IF;
END;
$$ LANGUAGE plpgsql;

-- token, source lang, target lang, text, category
CREATE OR REPLACE FUNCTION translation_proxy._bing_translate_curl(TEXT, CHAR(2), CHAR(2), TEXT) RETURNS TEXT AS $$
#!/bin/sh
TOKEN=$1
SRC=$2
DST=$3
QUERY=$4
$CTG=$5
curl -X GET -H "Authorization: Bearer $TOKEN" \
  --data-urlencode "text=$QUERY" \
  --data-urlencode "from=$SRC" \
  --data-urlencode "to=$DST" \
  --data-urlencode "category=$CTG" \
  'https://api.cognitive.microsoft.com/sts/v1.0/Translate' 2>/dev/null
$$ LANGUAGE plsh;

CREATE OR REPLACE FUNCTION translation_proxy.bing_translate(source CHAR(2), target CHAR(2), qs TEXT[], profile TEXT DEFAULT '')
RETURNS text[] as $$
BEGIN
END;
$$ LANGUAGE plpgsql;
