-- Internal function to generate stats for a table if they don't exist
CREATE OR REPLACE FUNCTION @extschema@._CDB_GenerateStats(reloid REGCLASS)
RETURNS VOID
AS $$
DECLARE
  has_stats BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT * FROM pg_catalog.pg_statistic WHERE starelid = reloid
  ) INTO has_stats;
  IF NOT has_stats THEN
    EXECUTE Format('ANALYZE %s;', reloid);
  END IF;
END
$$ LANGUAGE 'plpgsql' VOLATILE STRICT PARALLEL UNSAFE SECURITY DEFINER;

-- Return a row count estimate of the result of a query using statistics
CREATE OR REPLACE FUNCTION @extschema@.CDB_EstimateRowCount(query text)
RETURNS Numeric
AS $$
DECLARE
  plan JSON;
BEGIN
  -- Make sure statistics exist for all the tables of the query
  PERFORM @extschema@._CDB_GenerateStats(tabname) FROM  unnest(@extschema@.CDB_QueryTablesText(query)) AS tabname;

  -- Use the query planner to obtain an estimate of the number of result rows
  EXECUTE 'EXPLAIN (FORMAT JSON) ' || query INTO STRICT plan;
  RETURN plan->0->'Plan'->'Plan Rows';
END
$$ LANGUAGE 'plpgsql' VOLATILE STRICT PARALLEL UNSAFE;
