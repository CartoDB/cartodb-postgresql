-- continuous uniform distribution has kurtosis = -6/5, skewness = 0.0
-- http://mathworld.wolfram.com/UniformDistribution.html
set client_min_messages to ERROR;

WITH dist AS (
  SELECT generate_series(0,10000)::numeric / 10000.0 i
)
SELECT
  abs(CDB_Kurtosis(array_agg(i)) + 1.2) < 1e-3 AS kurtosis,
  abs(CDB_Skewness(array_agg(i))) < 1e-3 AS skewness
FROM dist;

set client_min_messages to NOTICE;
