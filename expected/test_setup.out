SET client_min_messages TO error;
CREATE EXTENSION cartodb CASCADE;
CREATE FUNCTION public.cdb_invalidate_varnish(table_name text)
RETURNS void AS $$
BEGIN
  RAISE NOTICE 'cdb_invalidate_varnish(%) called', table_name;
END;
$$ LANGUAGE 'plpgsql';
