-- continuous uniform distribution has kurtosis = -6/5, skewness = 0.0
-- http://mathworld.wolfram.com/UniformDistribution.html
set client_min_messages to ERROR;

With dist As (
  SELECT random()::numeric As val
  FROM generate_series(1,50000) t
)

SELECT 
  -- does random dist values match within 1% of known values
  abs(CDB_Kurtosis(array_agg(val)) + 1.20) < 1e-2 As kurtosis,
  abs(CDB_Skewness(array_agg(val)) - 0) < 1e-2 As skewness
FROM dist;

set client_min_messages to NOTICE;
