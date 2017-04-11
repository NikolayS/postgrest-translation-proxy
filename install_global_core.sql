create schema if not exists translation_proxy;
create extension if not exists plsh;

create table translation_proxy.cache(
    id bigserial primary key,
    source char(2) not null,
    target char(2) not null,
    q text not null,
    result text not null,
    created timestamp not null default now(),
    api_engine text not null
);
create unique index u_cache_q_source_target on translation_proxy.cache
    using btree(md5(q), source, target);

comment on table translation_proxy.cache is 'Cache for Translation proxy API calls';
