-- Maximum supported zoom level
CREATE OR REPLACE FUNCTION @extschema@._CDB_MaxSupportedZoom()
RETURNS int
LANGUAGE SQL
IMMUTABLE PARALLEL SAFE
AS $$
  -- The maximum zoom level has to be limited for various reasons,
  -- e.g. zoom levels greater than 31 would require tile coordinates
  -- that would not fit in an INTEGER (which is signed, 32 bits long).
  -- We'll choose 20 as a limit which is safe also when the JavaScript shift
  -- operator (<<) is used for computing powers of two.
  SELECT 29;
$$;

CREATE OR REPLACE FUNCTION @extschema@.CDB_ZoomFromScale(scaleDenominator numeric)
RETURNS int
LANGUAGE SQL
IMMUTABLE PARALLEL SAFE
AS $$
  SELECT
    CASE
      WHEN scaleDenominator > 600000000 THEN
        -- Scale is smaller than zoom level 0
        NULL
      WHEN scaleDenominator = 0 THEN
        -- Actual zoom level would be infinite
        @extschema@._CDB_MaxSupportedZoom()
      ELSE
        CAST (
          LEAST(
            ROUND(LOG(2, 559082264.028/scaleDenominator)),
            @extschema@._CDB_MaxSupportedZoom()
          )
        AS INTEGER)
    END;
$$;
