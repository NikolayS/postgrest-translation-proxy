create extension plsh;

create or replace function urlencode(in_str text, out _result text) returns text as $$
declare
    _i      int4;
    _temp   varchar;
    _ascii  int4;
begin
    _result := '';
    for _i in 1 .. length(in_str) loop
        _temp := substr(in_str, _i, 1);
        if _temp ~ '[0-9a-za-z:/@._?#-]+' then
            _result := _result || _temp;
        else
            _ascii := ascii(_temp);
            if _ascii > x'07ff'::int4 then
                raise exception 'won''t deal with 3 (or more) byte sequences.';
            end if;
            if _ascii <= x'07f'::int4 then
                _temp := '%'||to_hex(_ascii);
            else
                _temp := '%'||to_hex((_ascii & x'03f'::int4)+x'80'::int4);
                _ascii := _ascii >> 6;
                _temp := '%'||to_hex((_ascii & x'01f'::int4)+x'c0'::int4)
                            ||_temp;
            end if;
            _result := _result || upper(_temp);
        end if;
    end loop;
    return ;
end;
$$ language plpgsql;

