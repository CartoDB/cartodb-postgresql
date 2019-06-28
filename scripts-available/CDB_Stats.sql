--
-- Calculate basic statistics of a given dataset
--
-- @param in_array A numeric array of numbers
--
-- Returns: statistical quantity chosen
--
-- References: http://www.itl.nist.gov/div898/handbook/eda/section3/eda35b.htm
--

-- Calculate kurtosis
CREATE OR REPLACE FUNCTION @extschema@.CDB_Kurtosis ( in_array NUMERIC[] ) RETURNS NUMERIC as $$
DECLARE
    a numeric;
    c numeric;
    k numeric;
BEGIN
    SELECT AVG(e), COUNT(e)::numeric * power(stddev(e),4) INTO a, c FROM ( SELECT unnest(in_array) e ) x;

    IF c=0 THEN
      RETURN 0;
    ELSE

      EXECUTE 'SELECT sum(power($1 - e, 4)) / ($2 ) - 3
             FROM (SELECT unnest($3) e ) x'
      INTO k
      USING a, c, in_array;

      RETURN k;
    END IF;
END;
$$ language plpgsql IMMUTABLE STRICT PARALLEL SAFE;

-- Calculate skewness
CREATE OR REPLACE FUNCTION @extschema@.CDB_Skewness ( in_array NUMERIC[] ) RETURNS NUMERIC as $$
DECLARE
    a numeric;
    c numeric;
    sk numeric;
BEGIN
    SELECT AVG(e), COUNT(e)::numeric * power(stddev(e),3) INTO a, c FROM ( SELECT unnest(in_array) e ) x;
    IF c=0 THEN
      RETURN 0;
    ELSE
      EXECUTE 'SELECT sum(power($1 - e, 3)) / ( $2 )
             FROM (SELECT unnest($3) e ) x'
      INTO sk
      USING a, c, in_array;

      RETURN sk;
    END IF;
END;
$$ language plpgsql IMMUTABLE STRICT PARALLEL SAFE;
