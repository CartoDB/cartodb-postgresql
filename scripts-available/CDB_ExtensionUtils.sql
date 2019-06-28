CREATE OR REPLACE FUNCTION @extschema@.cdb_extension_reload() RETURNS void
AS $$
DECLARE
  ver TEXT;
  sql TEXT;
BEGIN
  ver := split_part(@extschema@.cdb_version(), ' ', 1);
  sql := 'ALTER EXTENSION cartodb UPDATE TO ''' || ver || 'next''';
  EXECUTE sql;
  sql := 'ALTER EXTENSION cartodb UPDATE TO ''' || ver || '''';
  EXECUTE sql;
END;
$$ language 'plpgsql' VOLATILE PARALLEL UNSAFE;

CREATE OR REPLACE FUNCTION @extschema@.schema_exists(schema_name text)
RETURNS boolean AS
$$
  SELECT EXISTS(SELECT 1 FROM pg_namespace WHERE nspname = schema_name::text);
$$
language sql STABLE PARALLEL SAFE;
