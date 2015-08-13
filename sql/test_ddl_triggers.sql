\set VERBOSITY terse

-- Set user quota to infinite
SELECT CDB_SetUserQuotaInBytes(0);

-- Enable ddl triggers
SELECT cartodb.cdb_enable_ddl_hooks();

create schema c;

SELECT CDB_SetUserQuotaInBytes('c', 0);

DROP USER IF EXISTS cartodb_postgresql_unpriv_user;
CREATE USER cartodb_postgresql_unpriv_user;
GRANT ALL ON SCHEMA c to cartodb_postgresql_unpriv_user;
SET SESSION AUTHORIZATION 'cartodb_postgresql_unpriv_user';
--SELECT session_user, current_user;

----------------------
-- CREATE TABLE
----------------------
SET SESSION AUTHORIZATION 'cartodb_postgresql_unpriv_user';
select 1 as i INTO c.t3;

RESET SESSION AUTHORIZATION;
select
 tabname::text,
 round(extract('secs' from now()  - updated_at)) as age
FROM CDB_TableMetadata WHERE tabname = 'c.t3'::regclass;

SET SESSION AUTHORIZATION 'cartodb_postgresql_unpriv_user';
-- Table with cartodb_id field, see
-- http://github.com/CartoDB/cartodb-postgresql/issues/32
select 1 as cartodb_id INTO c.t4;

RESET SESSION AUTHORIZATION;
select
 tabname::text,
 round(extract('secs' from now() - updated_at)) as age
FROM CDB_TableMetadata WHERE tabname = 'c.t4'::regclass;

----------------------------
-- ALTER TABLE RENAME COLUMN
----------------------------
SET SESSION AUTHORIZATION 'cartodb_postgresql_unpriv_user';

select pg_sleep(.1);
alter table c.t3 rename column the_geom_webmercator to webmerc;

RESET SESSION AUTHORIZATION;
select
 tabname::text,
 round(extract('secs' from now()  - updated_at)*10) as agecs
FROM CDB_TableMetadata WHERE tabname = 'c.t3'::regclass;

SET SESSION AUTHORIZATION 'cartodb_postgresql_unpriv_user';
select pg_sleep(.1);
alter table c.t3 rename column the_geom_webmercator to webmerc2;

RESET SESSION AUTHORIZATION;
select
 tabname::text,
 round(extract('secs' from now()  - updated_at)*10) as agecs
FROM CDB_TableMetadata WHERE tabname = 'c.t3'::regclass;

----------------------------
-- ALTER TABLE DROP COLUMN
----------------------------
SET SESSION AUTHORIZATION 'cartodb_postgresql_unpriv_user';
select pg_sleep(.1);
alter table c.t3 drop column the_geom_webmercator;

RESET SESSION AUTHORIZATION;
select
 tabname::text,
 round(extract('secs' from now()  - updated_at)*10) as agecs
FROM CDB_TableMetadata WHERE tabname = 'c.t3'::regclass;

----------------------------
-- ALTER TABLE ADD COLUMN
----------------------------
SET SESSION AUTHORIZATION 'cartodb_postgresql_unpriv_user';
select pg_sleep(.1);
alter table c.t3 add column id2 int;

RESET SESSION AUTHORIZATION;
select
 tabname::text,
 round(extract('secs' from now()  - updated_at)*10) as agecs
FROM CDB_TableMetadata WHERE tabname = 'c.t3'::regclass;

----------------------------
-- DROP TABLE
----------------------------

RESET SESSION AUTHORIZATION;
drop schema c cascade;
select count(*) from CDB_TableMetadata;

DROP USER cartodb_postgresql_unpriv_user;
DROP FUNCTION _CDB_UserQuotaInBytes();
