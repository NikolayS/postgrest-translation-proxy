-- there are dragons! Drop them with caution!

DROP FUNCTION IF EXISTS v1.google_translate(char, char, text);
DROP FUNCTION IF EXISTS v1.google_translate_array(char, char, json);

DROP FUNCTION IF EXISTS v1.promt_translate(char, char, text);
DROP FUNCTION IF EXISTS v1.promt_translate_array(char, char, json);

DROP FUNCTION IF EXISTS v1.bing_translate(char, char, text);
DROP FUNCTION IF EXISTS v1.bing_translate_array(char, char, json);
-- revoke usage on schema v1 from apiuser;
-- drop schema v1 cascade;
-- drop role apiuser;

DROP FUNCTION IF EXISTS v2.translate_array(CHAR(2), CHAR(2), JSON)

-- REVOKE USAGE ON SCHEMA v2 FROM apiuser;
-- DROP SCHEMA v2 CASCADE;
-- DROP ROLE apiuser;
