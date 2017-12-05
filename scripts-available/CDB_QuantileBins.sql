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
  SELECT array_agg(p) FROM (
      SELECT percentile_disc(idx::numeric / breaks::numeric)
        WITHIN GROUP (ORDER BY x ASC) AS p
      FROM generate_series(1, breaks) AS idx, unnest(in_array) AS x
      GROUP BY idx
  ) AS quantiles;
$$ language sql;
