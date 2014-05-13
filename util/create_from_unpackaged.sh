#!/bin/sh

ver=$1
input=cartodb--${ver}.sql
output=cartodb--unpackaged--${ver}.sql

cat ${input} > ${output}

# Migrate CDB_TableMetadata
cat >> ${output} <<'EOF'
ALTER TABLE cartodb.CDB_TableMetadata DISABLE TRIGGER ALL;
INSERT INTO cartodb.CDB_TableMetadata SELECT * FROM public.CDB_TableMetadata;
ALTER TABLE cartodb.CDB_TableMetadata ENABLE TRIGGER ALL;
DROP TABLE public.CDB_TableMetadata;

-- Set user quota
-- NOTE: will fail if user quota wasn't set at database level, see
--       http://github.com/CartoDB/cartodb-postgresql/issues/18
DO $$
DECLARE
  qmax int8;
BEGIN
  BEGIN
    qmax := public._CDB_UserQuotaInBytes();
  EXCEPTION WHEN undefined_function THEN
    RAISE EXCEPTION 'Please set user quota before switching to cartodb extension';
  END;
  PERFORM cartodb.CDB_SetUserQuotaInBytes(qmax);
  DROP FUNCTION public._CDB_UserQuotaInBytes();
END;
$$ LANGUAGE 'plpgsql';

-- Cartodbfy tables with a trigger using 'CDB_CheckQuota' or
-- 'CDB_TableMetadata_Trigger' from the 'public' schema
select cartodb.CDB_CartodbfyTable(relname::regclass) from ( 
  -- names of tables using public.CDB_CheckQuota or
  -- public.CDB_TableMetadata_Trigger in their triggers
  SELECT distinct c.relname
  FROM
    pg_trigger t,
    pg_class c,
    pg_proc p,
    pg_namespace n
  WHERE
    n.nspname = 'public' AND
    p.pronamespace = n.oid AND
    p.proname IN ( 'cdb_checkquota', 'cdb_tablemetadata_trigger' ) AND
    t.tgrelid = c.oid AND
    p.oid = t.tgfoid 
) as foo;
EOF

# Drop functions from public schema
cat ${input} |
  grep '^ *CREATE OR REPLACE FUNCTION' |
  grep -v ' cartodb\.' | # should  only match DDL hooks
  sed 's/).*$/);/' |
  sed 's/DEFAULT [^ ,)]*//g' |
  sed 's/CREATE OR REPLACE FUNCTION /DROP FUNCTION public./' |
  cat >> ${output}
