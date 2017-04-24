CREATE SCHEMA IF NOT EXISTS translation_proxy;
CREATE EXTENSION IF NOT EXISTS plsh;
CREATE EXTENSION IF NOT EXISTS plpython2u;

CREATE TYPE translation_proxy.api_engine_type AS ENUM ('google', 'promt', 'bing');

CREATE TABLE translation_proxy.cache(
    id BIGSERIAL PRIMARY KEY,
    source char(2) NOT NULL,
    target char(2) NOT NULL,
    q TEXT NOT NULL,
    result TEXT NOT NULL,
    profile TEXT NOT NULL DEFAULT '',
    created TIMESTAMP NOT NULL DEFAULT now(),
    api_engine translation_proxy.api_engine_type NOT NULL,
    encoded TEXT
);

CREATE UNIQUE INDEX u_cache_q_source_target ON translation_proxy.cache
    USING btree(md5(q), source, target, api_engine, profile);

COMMENT ON TABLE translation_proxy.cache IS 'The cache for API calls of the Translation proxy';

CREATE TABLE translation_proxy.authcache(
  api_engine translation_proxy.api_engine_type NOT NULL,
  creds TEXT,
  updated TIMESTAMP NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX u_authcache_engine ON translation_proxy.authcache ( api_engine );

COMMENT ON TABLE translation_proxy.authcache IS 'Translation API cache for remote authorization keys';

INSERT INTO translation_proxy.authcache (api_engine) VALUES ('google'), ('promt'), ('bing')
  ON CONFLICT DO NOTHING;

CREATE TABLE translation_proxy.detection_cache(
  id BIGSERIAL PRIMARY KEY,
  q TEXT NOT NULL,
  lang CHAR(2) NOT NULL,
  api_engine translation_proxy.api_engine_type NOT NULL,
  created TIMESTAMP NOT NULL DEFAULT now()
);

COMMENT ON TABLE translation_proxy.cache IS 'The cache for API calls for a language detection of the Translation proxy';

CREATE UNIQUE INDEX u_detectioncache_q_lang ON translation_proxy.detection_cache
  USING btree(md5(q), lang, api_engine);

CREATE OR REPLACE FUNCTION translation_proxy._save_cookie(engine translation_proxy.api_engine_type, cookie TEXT)
RETURNS VOID AS $$
BEGIN
  UPDATE translation_proxy.authcache
    SET ( creds, updated ) = ( cookie, now() )
    WHERE api_engine = engine;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION translation_proxy._load_cookie(engine translation_proxy.api_engine_type)
RETURNS TEXT AS $$
DECLARE
  cookie TEXT;
BEGIN
  SELECT creds INTO cookie FROM translation_proxy.authcache
  WHERE api_engine = engine AND
    updated > ( now() - current_setting('translation_proxy.promt.login_timeout')::INTERVAL )
    AND creds IS NOT NULL AND creds <> ''
  LIMIT 1;
  RETURN cookie;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION translation_proxy._find_detected_language(
  qs TEXT, engine translation_proxy.api_engine_type)
RETURNS TEXT AS $$
DECLARE
  lng CHAR(2);
BEGIN
  SELECT lang INTO lng FROM translation_proxy.detection_cache
    WHERE api_engine = engine AND
      q = qs
      LIMIT 1;
  RETURN lng;
END;
$$ LANGUAGE plpgsql;

-- trigger, that URLencodes query in cache, when no translation is given
CREATE OR REPLACE FUNCTION translation_proxy._urlencode_fields()
RETURNS TRIGGER AS $BODY$
  from urllib import quote_plus
  TD['new']['encoded'] =  quote_plus( TD['new']['q'] )
  return 'MODIFY'
$BODY$ LANGUAGE plpython2u;

CREATE TRIGGER _prepare_for_fetch BEFORE INSERT ON translation_proxy.cache
  FOR EACH ROW
  WHEN (NEW.result IS NULL)
  EXECUTE PROCEDURE translation_proxy._urlencode_fields();

-- adding new parameter to url until it exceeds the limit of 2000 bytes
CREATE OR REPLACE FUNCTION translation_proxy._urladd( url TEXT, a TEXT ) RETURNS TEXT AS $$
  from urllib import quote_plus
  r = url + '&' + quote_plus( a )
  if len(r) > 1999 :
    plpy.error('URL length is over, time to fetch.', errcode = 'EOURL')
  return r
$$ LANGUAGE plpython2u;

-- urlencoding utility
CREATE OR REPLACE FUNCTION translation_proxy._urlencode(q TEXT)
RETURNS TEXT AS $BODY$
  from urllib import quote_plus
  return quote_plus( q )
$BODY$ LANGUAGE plpython2u;
