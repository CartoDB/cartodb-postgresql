\i cartodb_hooks.sql
\set VERBOSITY terse

SET SESSION AUTHORIZATION 'development_cartodb_user_1';

SELECT session_user, current_user;


create schema c;
--create table c.t3(a int);
select 1 as i INTO c.t3;
select * from c.t3;
alter table c.t3 rename column the_geom_webmercator to webmerc;
select * from c.t3;
alter table c.t3 rename column the_geom_webmercator to webmerc2;
select * from c.t3;
alter table c.t3 drop column the_geom_webmercator;
select * from c.t3;
alter table c.t3 add column id2 int;
select * from c.t3;
drop schema c cascade;
