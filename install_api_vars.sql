ALTER DATABASE DBNAME SET translation_proxy.api.current_engine = 'CURRENT_API_ENGINE';

CREATE SCHEMA IF NOT EXISTS v1;
DO
$$
BEGIN
   IF NOT EXISTS (
      SELECT *
      FROM pg_catalog.pg_user
      WHERE  usename = 'apiuser'
    ) THEN
      CREATE ROLE apiuser PASSWORD 'APIUSER-PASSWORD' LOGIN;
   END IF;
END
$$;

GRANT USAGE ON SCHEMA v1 TO apiuser;
