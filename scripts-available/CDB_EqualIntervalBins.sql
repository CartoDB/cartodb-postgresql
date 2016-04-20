--
-- Calculate the equal interval bins for a given column
--
-- @param in_array A numeric or double precision array of numbers to determine the best
--                   to determine the bin boundary
--
-- @param breaks The number of bins you want to find.
--  
--
-- Returns: upper edges of bins
-- 
--
CREATE OR REPLACE FUNCTION CDB_EqualIntervalBins ( in_array NUMERIC[], breaks INT ) RETURNS NUMERIC[] as $$
WITH stats AS (
  SELECT min(e), (max(e)-min(e))/breaks AS del
    FROM (SELECT unnest(in_array) e) AS p)
SELECT array_agg(bins)
  FROM (
    SELECT min + generate_series(1,breaks)*del AS bins
      FROM stats) q;
$$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION CDB_EqualIntervalBins ( in_array double precision[], breaks INT ) RETURNS double precision[] as $$
WITH stats AS (
  SELECT min(e), (max(e)-min(e))/breaks AS del
    FROM (SELECT unnest(in_array) e) AS p)
SELECT array_agg(bins)
  FROM (
    SELECT min + generate_series(1,breaks)*del AS bins
      FROM stats) q;
$$ LANGUAGE SQL IMMUTABLE;
