revoke execute on function v2.google_translate(char, char, text) from apiuser;
revoke execute on function v2.google_translate_array(char, char, json) from apiuser;

revoke execute on function v2.promt_translate(char, char, text) from apiuser;
revoke execute on function v2.promt_translate_array(char, char, json) from apiuser;

revoke execute on function v2.bing_translate(char, char, text) from apiuser;
revoke execute on function v2.bing_translate_array(char, char, json) from apiuser;

drop function v2.google_translate(char, char, text);
drop function v2.google_translate_array(char, char, json);

drop function v2.promt_translate(char, char, text);
drop function v2.promt_translate_array(char, char, json);

drop function v2.bing_translate(char, char, text);
drop function v2.bing_translate_array(char, char, json);
--revoke usage on schema v2 from apiuser;
--drop schema v2 cascade;
--drop role apiuser;
