\set ECHO none
\set QUIET on
SET client_min_messages TO error;
CREATE EXTENSION postgis;
CREATE EXTENSION plpythonu;
CREATE SCHEMA cartodb;
\i 'cartodb--unpackaged--@@VERSION@@.sql'
CREATE FUNCTION public.cdb_invalidate_varnish(table_name text)
RETURNS void AS $$
BEGIN
  RAISE NOTICE 'cdb_invalidate_varnish(%) called', table_name;
END;
$$ LANGUAGE 'plpgsql';
\set QUIET off
