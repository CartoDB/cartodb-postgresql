-- continuous uniform distribution has kurtosis = -6/5, skewness = 0.0
-- http://mathworld.wolfram.com/UniformDistribution.html

With dist As (
  SELECT random() As val
  FROM generate_series(1,5000000) t
),
m As (
  SELECT avg(val) mn, count(*) cnt, stddev(val) s
  FROM dist
  )

SELECT 
  abs(sum(power(mn - val,4)) / ( cnt * power(s,4)) - 3 + 1.20) < 1e-3 As kurtosis,
  abs(sum(power(mn - val,3)) / ( cnt * power(s,3))) < 1e-3 As skewness
FROM dist, m
GROUP BY m.cnt, m.mn, m.s