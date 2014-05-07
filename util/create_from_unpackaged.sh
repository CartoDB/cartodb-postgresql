#!/bin/sh

input=cartodb--0.1.sql
output=cartodb--unpackaged--0.1.sql

cat ${input} > ${output}

# Migrate CDB_TableMetadata
cat >> ${output} <<EOF
ALTER TABLE cartodb.CDB_TableMetadata DISABLE TRIGGER ALL;
INSERT INTO cartodb.CDB_TableMetadata SELECT * FROM public.CDB_TableMetadata;
ALTER TABLE cartodb.CDB_TableMetadata ENABLE TRIGGER ALL;
DROP TABLE public.CDB_TableMetadata;

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
