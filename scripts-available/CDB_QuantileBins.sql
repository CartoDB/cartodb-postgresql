--
-- Determine the Quantile classifications from a numeric array
--
-- @param in_array A numeric array of numbers to determine the best
--            bins based on the Quantile method.
--
-- @param breaks The number of bins you want to find.
--
--
CREATE OR REPLACE FUNCTION CDB_QuantileBins(in_array numeric[], breaks int)
RETURNS numeric[]
AS $$
  SELECT
    percentile_disc(Array(SELECT generate_series(1, breaks) / breaks::numeric))
    WITHIN GROUP (ORDER BY x ASC) AS p
  FROM
    unnest(in_array) AS x;
$$ language SQL IMMUTABLE STRICT PARALLEL SAFE;
