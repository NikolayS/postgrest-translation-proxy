-- there are dragons! Drop them with caution!
revoke execute on function v1.google_translate(char, char, text) from apiuser;
revoke execute on function v1.google_translate_array(char, char, json) from apiuser;

revoke execute on function v1.promt_translate(char, char, text) from apiuser;
revoke execute on function v1.promt_translate_array(char, char, json) from apiuser;

revoke execute on function v1.bing_translate(char, char, text) from apiuser;
revoke execute on function v1.bing_translate_array(char, char, json) from apiuser;

drop function v1.google_translate(char, char, text);
drop function v1.google_translate_array(char, char, json);

drop function v1.promt_translate(char, char, text);
drop function v1.promt_translate_array(char, char, json);

drop function v1.bing_translate(char, char, text);
drop function v1.bing_translate_array(char, char, json);
-- revoke usage on schema v1 from apiuser;
-- drop schema v1 cascade;
-- drop role apiuser;

revoke execute on function v2.translate_array(CHAR(2), CHAR(2), JSON)
drop function v2.translate_array(CHAR(2), CHAR(2), JSON)

-- REVOKE USAGE ON SCHEMA v2 FROM apiuser;
-- DROP SCHEMA v2 CASCADE;
-- DROP ROLE apiuser;
