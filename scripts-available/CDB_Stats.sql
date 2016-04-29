--
-- Calculate basic statistics of a given dataset
--
-- @param in_array A numeric array of numbers
--
-- Returns: statistical quantity chosen
-- 
-- References:
-- http://www.itl.nist.gov/div898/handbook/eda/section3/eda35b.htm
-- http://mathworld.wolfram.com/CentralMoment.html
-- http://researcher.watson.ibm.com/researcher/files/us-ytian/numerical_stability_icde2012.pdf

-- Calculate excess kurtosis
-- This uses the standard two-pass method, calculating the average and then on
-- the second pass calculating using the 4th central moment and 2nd central moment
-- (stddev^2).
-- This is more accurate than a single-pass calculating from raw moments, which
-- accumlates floating point error badly.
-- References: http://mathworld.wolfram.com/Kurtosis.html
CREATE OR REPLACE FUNCTION CDB_Kurtosis ( in_array smallint[] ) RETURNS numeric as $$
WITH pass1 AS (SELECT avg(x) a FROM (SELECT unnest(in_array) x) q) -- first pass calculate average
SELECT (avg(power(x-a, 4))/power(stddev_pop(x),4) - 3)::numeric
  FROM pass1, (SELECT unnest(in_array) x) q;
$$ LANGUAGE SQL IMMUTABLE;
CREATE OR REPLACE FUNCTION CDB_Kurtosis ( in_array int[] ) RETURNS numeric as $$
WITH pass1 AS (SELECT avg(x) a FROM (SELECT unnest(in_array) x) q) -- first pass calculate average
SELECT (avg(power(x-a, 4))/power(stddev_pop(x),4) - 3)::numeric
  FROM pass1, (SELECT unnest(in_array) x) q;
$$ LANGUAGE SQL IMMUTABLE;
CREATE OR REPLACE FUNCTION CDB_Kurtosis ( in_array bigint[] ) RETURNS numeric as $$
WITH pass1 AS (SELECT avg(x) a FROM (SELECT unnest(in_array) x) q) -- first pass calculate average
SELECT (avg(power(x-a, 4))/power(stddev_pop(x),4) - 3)::numeric
  FROM pass1, (SELECT unnest(in_array) x) q;
$$ LANGUAGE SQL IMMUTABLE;
CREATE OR REPLACE FUNCTION CDB_Kurtosis ( in_array real[] ) RETURNS double precision as $$
WITH pass1 AS (SELECT avg(x) a FROM (SELECT unnest(in_array) x) q) -- first pass calculate average
SELECT (avg(power(x-a, 4))/power(stddev_pop(x),4) - 3)::double precision
  FROM pass1, (SELECT unnest(in_array) x) q;
$$ LANGUAGE SQL IMMUTABLE;
CREATE OR REPLACE FUNCTION CDB_Kurtosis ( in_array double precision[] ) RETURNS double precision as $$
WITH pass1 AS (SELECT avg(x) a FROM (SELECT unnest(in_array) x) q) -- first pass calculate average
SELECT (avg(power(x-a, 4))/power(stddev_pop(x),4) - 3)::double precision
  FROM pass1, (SELECT unnest(in_array) x) q;
$$ LANGUAGE SQL IMMUTABLE;
CREATE OR REPLACE FUNCTION CDB_Kurtosis ( in_array numeric[] ) RETURNS numeric as $$
WITH pass1 AS (SELECT avg(x) a FROM (SELECT unnest(in_array) x) q) -- first pass calculate average
SELECT (avg(power(x-a, 4))/power(stddev_pop(x),4) - 3)::numeric
  FROM pass1, (SELECT unnest(in_array) x) q;
$$ LANGUAGE SQL IMMUTABLE;

-- Calculate skewness
-- This uses the same technique as CDB_Kurtosis, except with the 3rd central moment
-- References: http://mathworld.wolfram.com/Skewness.html
CREATE OR REPLACE FUNCTION CDB_Skewness ( in_array smallint[] ) RETURNS numeric as $$
WITH pass1 AS (SELECT avg(x) a FROM (SELECT unnest(in_array) x) q) -- first pass calculate average
SELECT (avg(power(x-a, 3))/power(stddev_pop(x),3))::numeric FROM pass1, (SELECT unnest(in_array) x) q;
$$ LANGUAGE SQL IMMUTABLE;
CREATE OR REPLACE FUNCTION CDB_Skewness ( in_array int[] ) RETURNS numeric as $$
WITH pass1 AS (SELECT avg(x) a FROM (SELECT unnest(in_array) x) q) -- first pass calculate average
SELECT (avg(power(x-a, 3))/power(stddev_pop(x),3))::numeric FROM pass1, (SELECT unnest(in_array) x) q;
$$ LANGUAGE SQL IMMUTABLE;
CREATE OR REPLACE FUNCTION CDB_Skewness ( in_array bigint[] ) RETURNS NUMERIC as $$
WITH pass1 AS (SELECT avg(x) a FROM (SELECT unnest(in_array) x) q) -- first pass calculate average
SELECT (avg(power(x-a, 3))/power(stddev_pop(x),3))::numeric FROM pass1, (SELECT unnest(in_array) x) q;
$$ LANGUAGE SQL IMMUTABLE;
CREATE OR REPLACE FUNCTION CDB_Skewness ( in_array real[] ) RETURNS double precision as $$
WITH pass1 AS (SELECT avg(x) a FROM (SELECT unnest(in_array) x) q) -- first pass calculate average
SELECT (avg(power(x-a, 3))/power(stddev_pop(x),3))::double precision FROM pass1, (SELECT unnest(in_array) x) q;
$$ LANGUAGE SQL IMMUTABLE;
CREATE OR REPLACE FUNCTION CDB_Skewness ( in_array double precision[] ) RETURNS double precision as $$
WITH pass1 AS (SELECT avg(x) a FROM (SELECT unnest(in_array) x) q) -- first pass calculate average
SELECT (avg(power(x-a, 3))/power(stddev_pop(x),3))::double precision FROM pass1, (SELECT unnest(in_array) x) q;
$$ LANGUAGE SQL IMMUTABLE;
CREATE OR REPLACE FUNCTION CDB_Skewness ( in_array numeric[] ) RETURNS numeric as $$
WITH pass1 AS (SELECT avg(x) a FROM (SELECT unnest(in_array) x) q) -- first pass calculate average
SELECT (avg(power(x-a, 3))/power(stddev_pop(x),3))::numeric FROM pass1, (SELECT unnest(in_array) x) q;
$$ LANGUAGE SQL IMMUTABLE;
