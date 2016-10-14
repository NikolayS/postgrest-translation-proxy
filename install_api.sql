create schema if not exists v1;
do
$$
begin
   if not exists (
      select *
      from   pg_catalog.pg_user
      where  usename = 'apiuser'
    ) then
      create role my_user password 'SOMEPASSWORD' login;
   end if;
end
$$;

grant usage on schema v1 to apiuser;

create or replace function v1.google_translate(source char(2), target char(2), q text) returns text as $$
    select * from google_translate.translate(source, target, q);
$$ language sql security invoker;

grant execute on function v1.google_translate(char, char, text) to apiuser;
