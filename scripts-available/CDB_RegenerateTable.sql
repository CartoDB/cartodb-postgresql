--
-- Given a table, returns a series of queries that can be used to recreate it
-- It does not include data
--
CREATE OR REPLACE FUNCTION @extschema@.__CDB_RegenerateTable_Get_Commands(tableoid OID)
RETURNS text[]
AS $$
    import subprocess
    import re

    query = "SELECT current_database()::text as dname"
    rv = plpy.execute(query, 1)
    database_name_string = str(rv[0]['dname'])

    query = """SELECT concat(quote_ident(nspname), '.', quote_ident(relname)) as quoted_name
                        FROM pg_catalog.pg_class AS c
                        JOIN pg_catalog.pg_namespace AS ns
                        ON c.relnamespace = ns.oid
                        WHERE c.oid = '%s'""" % (tableoid)
    rv = plpy.execute(query, 1)
    full_tablename_string = str(rv[0]['quoted_name'])

    # NOTE: We always use -s so data is never dumped!
    # That would be a security issue that we would need to deal with (and we currently do not need it)
    process_parameters = ["pg_dump", "-s", "--lock-wait-timeout", "1000", "-t", full_tablename_string, database_name_string]

    proc = subprocess.Popen(process_parameters, stdout=subprocess.PIPE, shell=False)
    (out, err) = proc.communicate()
    if (err or not out):
        plpy.error('Could not get table properties')

    line = out.decode("utf-8")
    lines = line.rsplit(";\n", -1)
    clean_lines = []
    for i in range(0, len(lines)):
        line = lines[i]
        sublines = line.splitlines()
        sublines = [line.rstrip() for line in sublines]
        sublines = [line for line in sublines if line]
        sublines = [line for line in sublines if not line.startswith('--')]
        sublines = [line for line in sublines if not line.lower().startswith('set ')]
        sublines = [line for line in sublines if line.lower().find('pg_catalog.set_config(') == -1]

        if len(sublines):
            clean_lines.append("".join(sublines))

    return clean_lines
$$
LANGUAGE @@plpythonu@@ VOLATILE PARALLEL UNSAFE;

-- Returns a list of queries that can be used to regenerate the structure of a table
-- The query to create the table is not included
-- The optional parameter **ignore_cartodbfication** will remove queries related to the cartodbfication of the table
CREATE OR REPLACE FUNCTION @extschema@.CDB_GetTableQueries(tableoid OID, ignore_cartodbfication BOOL DEFAULT false)
RETURNS text[]
AS
$$
DECLARE
    children INTEGER;
    queries TEXT[];
BEGIN
    EXECUTE FORMAT ('SELECT count(*) FROM pg_catalog.pg_inherits WHERE inhparent =  %L', tableoid)
            INTO children;
    IF children > 0 THEN
        RAISE EXCEPTION 'CDB_GetTableQueries does not support the parent of partitioned tables';
    END IF;
    IF NOT ignore_cartodbfication THEN
        EXECUTE FORMAT('
            SELECT array_agg(a)
                FROM unnest(@extschema@.__CDB_RegenerateTable_Get_Commands(%L)) a
                WHERE   a NOT SIMILAR TO ''CREATE TABLE%%'';', tableoid) INTO queries;
    ELSE
        EXECUTE FORMAT('
            SELECT array_agg(a)
                FROM unnest(@extschema@.__CDB_RegenerateTable_Get_Commands(%L)) a
                WHERE   a NOT SIMILAR TO ''CREATE TABLE%%'' AND
                        a NOT SIMILAR TO (''%%PRIMARY KEY \(cartodb_id\)%%'') AND
                        a NOT SIMILAR TO (''%%cartodb_id_seq%%'') AND
                        a NOT SIMILAR TO (''%%track_updates%%'') AND
                        a NOT SIMILAR TO (''%%update_the_geom_webmercator_trigger%%'') AND
                        a NOT SIMILAR TO (''%%test_quota%%'') AND
                        a NOT SIMILAR TO (''%%test_quota_per_row%%'') AND
                        a NOT SIMILAR TO (''%%gist \(the_geom\)%%'') AND
                        a NOT SIMILAR TO (''%%gist \(the_geom_webmercator\)%%'');', tableoid) INTO queries;
    END IF;
    RETURN queries;
END
$$
LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;

-- Regenerates a table
CREATE OR REPLACE FUNCTION @extschema@.CDB_RegenerateTable(tableoid OID)
RETURNS void
AS
$$
DECLARE
    temp_name TEXT := 'temp_' || encode(sha224(random()::text::bytea), 'hex');
    table_name TEXT;
    queries TEXT[] := @extschema@.__CDB_RegenerateTable_Get_Commands(tableoid);
    i INTEGER;
    children INTEGER;
BEGIN
    EXECUTE FORMAT ('SELECT count(*) FROM pg_catalog.pg_inherits WHERE inhparent =  %L', tableoid)
            INTO children;
    IF children > 0 THEN
        RAISE EXCEPTION 'CDB_RegenerateTable does not support the parent of partitioned tables';
    END IF;

    EXECUTE FORMAT('SELECT concat(quote_ident(nspname), ''.'', quote_ident(relname)) as quoted_name
                        FROM pg_catalog.pg_class AS c
                        JOIN pg_catalog.pg_namespace AS ns
                        ON c.relnamespace = ns.oid
                        WHERE c.oid = %L', tableoid) INTO table_name;

    EXECUTE FORMAT('CREATE TEMPORARY TABLE %s ON COMMIT DROP AS SELECT * FROM %s', temp_name, table_name);
    EXECUTE FORMAT('DROP TABLE %s', table_name);

    FOR i IN 1 .. array_upper(queries, 1)
    LOOP
        EXECUTE queries[i];
    END LOOP;

    EXECUTE FORMAT('INSERT INTO %s SELECT * FROM %I', table_name, temp_name);
END
$$ LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;
