alter database DBNAME set translation_proxy.api.current_engine = 'CURRENT_API_ENGINE'

CREATE SCHEMA IF NOT EXISTS 'API_SCHEMA_NAME';
DO
$$
BEGIN
   IF NOT EXISTS (
      SELECT *
      FROM pg_catalog.pg_user
      WHERE  usename = 'API_USERNAME'
    ) THEN
      CREATE ROLE API_USERNAME PASSWORD 'APIUSER-PASSWORD' LOGIN;
   END IF;
END
$$;

GRANT USAGE ON SCHEMA 'API_SCHEMA_NAME' TO API_USERNAME;

CREATE OR REPLACE FUNCTION API_SCHEMA_NAME.translate_array(source CHAR(2), target CHAR(2), q JSON)
RETURNS TEXT[] AS $$
  CASE current_setting('translation_proxy.api.current_engine')
    WHEN 'google' THEN
      SELECT * FROM translation_proxy.google_translate_array( source, target, q );
    WHEN 'promt' THEN
      SELECT * FROM translation_proxy.promt_translate_array( source, target, q );
    WHEN 'bing' THEN
      SELECT * FROM translation_proxy.bing_translate_array( source, target, q );
  END CASE;
$$ LANGUAGE SQL SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION API_SCHEMA_NAME.translate_array(char, char, json) TO API_USERNAME;
