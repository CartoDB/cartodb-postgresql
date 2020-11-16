--
-- Given a table, returns a series of queries that can be used to recreate it
-- It does not include data
--
CREATE OR REPLACE FUNCTION @extschema@.__CDB_RegenerateTable_Get_Commands(tableoid OID)
RETURNS text[]
AS $$
    import subprocess

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
    process_parameters = ["pg_dump", "-s", "-t", full_tablename_string, database_name_string]

    proc = subprocess.Popen(process_parameters, stdout=subprocess.PIPE, shell=False)
    (out, err) = proc.communicate()
    if (err):
        plpy.error(err)

    line = out.decode("utf-8")
    lines = line.rsplit(";\n", -1)
    clean_lines = []
    for i in range(0, len(lines)):
        line = lines[i]
        sublines = line.splitlines()
        sublines = [line.rstrip() for line in sublines]
        sublines = [line for line in sublines if line]
        sublines = [line for line in sublines if not line.startswith('--')]
        if len(sublines):
            clean_lines.append("".join(sublines))

    # Add an extra query to reset the environment
    clean_lines.append("RESET ALL");

    return clean_lines
$$
LANGUAGE @@plpythonu@@ VOLATILE PARALLEL UNSAFE;

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
BEGIN
    EXECUTE FORMAT('SELECT concat(quote_ident(nspname), ''.'', quote_ident(relname)) as quoted_name
                        FROM pg_catalog.pg_class AS c
                        JOIN pg_catalog.pg_namespace AS ns
                        ON c.relnamespace = ns.oid
                        WHERE c.oid = %L', tableoid) INTO table_name;

    RAISE DEBUG '%', FORMAT('ALTER TABLE %s RENAME TO %s', table_name, temp_name);
    EXECUTE FORMAT('ALTER TABLE %s RENAME TO %s', table_name, temp_name);

    FOR i IN 1 .. array_upper(queries, 1)
    LOOP
        RAISE DEBUG '% - %', i, queries[i];
        EXECUTE queries[i];
    END LOOP;

    RAISE DEBUG '%', FORMAT('INSERT INTO %s SELECT * FROM %I', table_name, temp_name);
    EXECUTE FORMAT('INSERT INTO %s SELECT * FROM %I', table_name, temp_name);

    RAISE DEBUG '%', FORMAT('DROP TABLE %I', temp_name);
    EXECUTE FORMAT('DROP TABLE %I', temp_name);
END
$$ LANGUAGE PLPGSQL VOLATILE PARALLEL UNSAFE;
