CREATE SCHEMA IF NOT EXISTS translation_proxy;
CREATE EXTENSION IF NOT EXISTS plsh;
CREATE TYPE translation_proxy.api_engine_type AS ENUM ('google', 'promt', 'bing');

CREATE TABLE translation_proxy.cache(
    id BIGSERIAL PRIMARY KEY,
    source char(2) NOT NULL,
    target char(2) NOT NULL,
    q TEXT NOT NULL,
    result TEXT NOT NULL,
    created TIMESTAMP NOT NULL DEFAULT now(),
    api_engine translation_proxy.api_engine_type NOT NULL
);

CREATE UNIQUE INDEX u_cache_q_source_target ON translation_proxy.cache
    USING btree(md5(q), source, target, api_engine);

COMMENT ON TABLE translation_proxy.cache IS 'Cache for Translation proxy API calls';

CREATE TABLE translation_proxy.authcache(
  api_engine translation_proxy.api_engine_type NOT NULL,
  creds TEXT,
  updated TIMESTAMP NOT NULL DEFAULT now()
);

COMMENT ON TABLE translation_proxy.authcache IS 'Translation API cache for remote authorization keys';

INSERT INTO translation_proxy.authcache (api_engine) VALUES ('google'), ('promt'), ('bing');
