CREATE OR REPLACE FUNCTION cartodb.CDB_ZoomFromScale(scaleDenominator numeric)
RETURNS int
LANGUAGE SQL
IMMUTABLE
AS $$
SELECT
  CASE
  -- Don't bother if the scale is larger than ~zoom level 0
    WHEN scaleDenominator > 600000000 OR scaleDenominator = 0 THEN NULL
    ELSE CAST (ROUND(LOG(2, 559082264.028/scaleDenominator)) AS INTEGER)
  END;
$$;
