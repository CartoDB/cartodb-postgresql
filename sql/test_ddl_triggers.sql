\set VERBOSITY terse

-- Set user quota to infinite
SELECT CDB_SetUserQuotaInBytes(0);

-- Enable ddl triggers
SELECT cartodb.cdb_enable_ddl_hooks();

create schema c;

SELECT CDB_SetUserQuotaInBytes('c', 0);

CREATE USER cartodb_postgresql_unpriv_user;
GRANT ALL ON SCHEMA c to cartodb_postgresql_unpriv_user;
SET SESSION AUTHORIZATION 'cartodb_postgresql_unpriv_user';
--SELECT session_user, current_user;

----------------------
-- CREATE TABLE
----------------------

select 1 as i INTO c.t3;

select
 cartodb_id, created_at=updated_at as "c=u",
 NOW() - updated_at < '1 secs' as "u<1s",
 the_geom, the_geom_webmercator,
 i
from c.t3;

select
 tabname::text,
 round(extract('secs' from now()  - updated_at)) as age
FROM CDB_TableMetadata WHERE tabname = 'c.t3'::regclass;

-- Table with cartodb_id field, see
-- http://github.com/CartoDB/cartodb-postgresql/issues/32
select 1 as cartodb_id INTO c.t4;
select
 cartodb_id, created_at=updated_at as "c=u",
 NOW() - updated_at < '1 secs' as "u<1s",
 the_geom, the_geom_webmercator
from c.t4;
select
 tabname::text,
 round(extract('secs' from now() - updated_at)) as age
FROM CDB_TableMetadata WHERE tabname = 'c.t4'::regclass;

----------------------------
-- ALTER TABLE RENAME COLUMN
----------------------------

select pg_sleep(.1);
alter table c.t3 rename column the_geom_webmercator to webmerc;

select
 cartodb_id, created_at=updated_at as "c=u",
 NOW() - updated_at < '1 secs' as "u<1s",
 the_geom, the_geom_webmercator,
 i, webmerc
from c.t3;

select
 tabname::text,
 round(extract('secs' from now()  - updated_at)*10) as agecs
FROM CDB_TableMetadata WHERE tabname = 'c.t3'::regclass;

select pg_sleep(.1);
alter table c.t3 rename column the_geom_webmercator to webmerc2;

select
 cartodb_id, created_at=updated_at as "c=u",
 NOW() - updated_at < '1 secs' as "u<1s",
 the_geom, the_geom_webmercator,
 i, webmerc, webmerc2
from c.t3;

select
 tabname::text,
 round(extract('secs' from now()  - updated_at)*10) as agecs
FROM CDB_TableMetadata WHERE tabname = 'c.t3'::regclass;

----------------------------
-- ALTER TABLE DROP COLUMN
----------------------------

select pg_sleep(.1);
alter table c.t3 drop column the_geom_webmercator;

select
 cartodb_id, created_at=updated_at as "c=u",
 NOW() - updated_at < '1 secs' as "u<1s",
 the_geom, the_geom_webmercator,
 i, webmerc, webmerc2
from c.t3;

select
 tabname::text,
 round(extract('secs' from now()  - updated_at)*10) as agecs
FROM CDB_TableMetadata WHERE tabname = 'c.t3'::regclass;

----------------------------
-- ALTER TABLE ADD COLUMN
----------------------------

select pg_sleep(.1);
alter table c.t3 add column id2 int;

select
 cartodb_id, created_at=updated_at as "c=u",
 NOW() - updated_at < '1 secs' as "u<1s",
 the_geom, the_geom_webmercator,
 i, webmerc, webmerc2, id2
from c.t3;

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
