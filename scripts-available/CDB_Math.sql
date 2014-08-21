-- CartoDB Math SQL functions


-- Mode
-- https://wiki.postgresql.org/wiki/Aggregate_Mode

CREATE OR REPLACE FUNCTION cartodb._CDB_Math_final_mode(anyarray)
  RETURNS anyelement AS
$BODY$
    SELECT a
    FROM unnest($1) a
    GROUP BY 1 
    ORDER BY COUNT(1) DESC, 1
    LIMIT 1;
$BODY$
LANGUAGE 'sql' IMMUTABLE;

DROP AGGREGATE IF EXISTS cartodb.CDB_Math_Mode(anyelement);

CREATE AGGREGATE cartodb.CDB_Math_Mode(anyelement) (
  SFUNC=array_append,
  STYPE=anyarray,
  FINALFUNC=_CDB_Math_final_mode,
  INITCOND='{}'
);

