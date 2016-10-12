begin;

create schema v1;

create or replace function v1.google_translate(source char(2), target char(2), q text) returns text as $$
    select * from google_translate.translate(source, target, q);
$$ language sql;

commit;
