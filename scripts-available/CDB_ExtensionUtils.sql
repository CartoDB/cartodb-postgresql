CREATE OR REPLACE FUNCTION cartodb.cdb_extension_reload() RETURNS void
AS $$
DECLARE
  ver TEXT;
  sql TEXT;
BEGIN
  ver := split_part(cartodb.cdb_version(), ' ', 1);
  sql := 'ALTER EXTENSION cartodb UPDATE TO ''' || ver || 'next''';
  EXECUTE sql;
  sql := 'ALTER EXTENSION cartodb UPDATE TO ''' || ver || '''';
  EXECUTE sql;
END;
$$ language 'plpgsql' VOLATILE;
