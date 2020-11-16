--
-- Given a table
-- Replace cartodb ==> @extschema@
-- Replace plpython3u ==> @@plpythonu@@
--
CREATE OR REPLACE FUNCTION cartodb.__CDB_RegenerateTable_Get_Commands(tableoid OID)
RETURNS text
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

    lines = out.splitlines()
    lines = [line.rstrip() for line in lines]
    lines = [line for line in lines if line]
    lines = [line for line in lines if not line.startswith(b'--')]
    lines = [line.decode("utf-8") for line in lines]

    return "".join(lines)
$$
LANGUAGE plpython3u VOLATILE PARALLEL UNSAFE;
