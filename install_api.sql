create schema if not exists v2;
do
$$
begin
   if not exists (
      select *
      from   pg_catalog.pg_user
      where  usename = 'apiuser'
    ) then
      create role apiuser password 'pass-for-apiuser' login;
   end if;
end
$$;

grant usage on schema v2 to apiuser;
