SELECT current_user; -- postgres
SELECT CDB_Username(); -- (NULL)

-- Connect with admin
\set QUIET on
\o log/test.log
SELECT current_database() AS current_database;
\gset
SELECT SUBSTRING (:'current_database', 19, 36) AS user_id;
\gset
SELECT rolname AS admin_user FROM pg_roles where rolname LIKE ('%' || :'user_id');
\gset
\c :current_database :admin_user
\o
\set QUIET off

SELECT CDB_Username(); -- admin