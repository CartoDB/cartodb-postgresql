CREATE EXTENSION postgis;
CREATE EXTENSION plpythonu;
CREATE EXTENSION cartodb;
CREATE FUNCTION public.cdb_invalidate_varnish(table_name text)
RETURNS void AS $$
BEGIN
  RAISE NOTICE 'cdb_invalidate_varnish(%) called', table_name;
END;
$$ LANGUAGE 'plpgsql';
