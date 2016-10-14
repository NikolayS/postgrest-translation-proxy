revoke execute on function v1.google_translate(char, char, text) from apiuser;
drop function v1.google_translate(char, char, text);
--revoke usage on schema v1 from apiuser;
--drop schema v1 cascade;
--drop role apiuser;

