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
--revoke usage on schema v1 from apiuser;
--drop schema v1 cascade;
--drop role apiuser;
