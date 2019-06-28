-- CartoDB Math SQL functions


-- Mode
-- https://wiki.postgresql.org/wiki/Aggregate_Mode

CREATE OR REPLACE FUNCTION @extschema@._CDB_Math_final_mode(anyarray)
  RETURNS anyelement AS
$BODY$
    SELECT a
    FROM unnest($1) a
    GROUP BY 1 
    ORDER BY COUNT(1) DESC, 1
    LIMIT 1;
$BODY$
LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;

DROP AGGREGATE IF EXISTS @extschema@.CDB_Math_Mode(anyelement);

CREATE AGGREGATE @extschema@.CDB_Math_Mode(anyelement) (
  SFUNC=array_append,
  STYPE=anyarray,
  FINALFUNC=@extschema@._CDB_Math_final_mode,
  PARALLEL = SAFE,
  INITCOND='{}'
);

