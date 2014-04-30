CREATE EXTENSION postgis;
CREATE EXTENSION schema_triggers;
CREATE EXTENSION cartodb;

set search_path to public,cartodb,schema_triggers;

--set client_min_messages to debug;

-- Create a stub cdb_invalidate_varnish function if not available
--CREATE FUNCTION tmp() returns void AS $$
DO $$
BEGIN
  PERFORM cdb_invalidate_varnish(0);
EXCEPTION
  WHEN undefined_function THEN
    CREATE OR REPLACE FUNCTION cartodb.cdb_invalidate_varnish(tabname regclass)
    RETURNS void AS '' LANGUAGE 'sql';
END;
$$ LANGUAGE 'plpgsql';

--SELECT tmp();


create schema c;

CREATE TABLE IF NOT EXISTS
  public.CDB_TableMetadata (
    tabname regclass not null primary key,
    updated_at timestamp with time zone not null default now()
  );

CREATE USER cartodb_postgresql_unpriv_user;
GRANT ALL ON SCHEMA c to cartodb_postgresql_unpriv_user;
GRANT SELECT ON public.CDB_TableMetadata to cartodb_postgresql_unpriv_user;
SET SESSION AUTHORIZATION 'cartodb_postgresql_unpriv_user';
--SELECT session_user, current_user;


--create table c.t3(a int);
select 1 as i INTO c.t3;
select * from c.t3;
select tabname::text, updated_at from CDB_TableMetadata;
alter table c.t3 rename column the_geom_webmercator to webmerc;
select * from c.t3;
select tabname::text, updated_at from CDB_TableMetadata;
alter table c.t3 rename column the_geom_webmercator to webmerc2;
select * from c.t3;
select tabname::text, updated_at from CDB_TableMetadata;
alter table c.t3 drop column the_geom_webmercator;
select * from c.t3;
select tabname::text, updated_at from CDB_TableMetadata;
alter table c.t3 add column id2 int;
select * from c.t3;
select tabname::text, updated_at from CDB_TableMetadata;

RESET SESSION AUTHORIZATION;
drop schema c cascade;
select tabname::text, updated_at from CDB_TableMetadata;

DROP TABLE public.CDB_TableMetadata;
DROP USER cartodb_postgresql_unpriv_user;
