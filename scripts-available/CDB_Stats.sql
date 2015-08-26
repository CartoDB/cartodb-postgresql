--
-- Calculate basic statistics of a given dataset
--
-- @param in_array A numeric array of numbers
--
-- Returns: statistical quantity chosen
-- 
--

-- Calculate Pearson's moment coefficient of kurtosis
CREATE OR REPLACE FUNCTION CDB_Kurtosis ( in_array NUMERIC[] ) RETURNS NUMERIC as $$
DECLARE
    a numeric;
    c numeric;
    s numeric;
    k numeric;
BEGIN
    SELECT AVG(e), COUNT(e)::numeric, stddev(e) INTO a, c, s FROM ( SELECT unnest(in_array) e ) x;

    RAISE NOTICE 'avg: %, cnt: %, std: %', a, c, s;

    EXECUTE 'SELECT sum(power($1 - e, 4)) / ( $2 * power($3, 4))
             FROM (SELECT unnest($4) e ) x'
    INTO k
    USING a, c, s, in_array;

    RETURN k;
END;
$$ language plpgsql IMMUTABLE;

-- Calculate Pearson's moment coefficient of skewness
CREATE OR REPLACE FUNCTION CDB_Skewness ( in_array NUMERIC[] ) RETURNS NUMERIC as $$
DECLARE
    a numeric;
    c numeric;
    s numeric;
    sk numeric;
BEGIN
    SELECT AVG(e), COUNT(e)::numeric, stddev(e) INTO a, c, s FROM ( SELECT unnest(in_array) e ) x;

    RAISE NOTICE 'avg: %, cnt: %, std: %', a, c, s;

    EXECUTE 'SELECT sum(power($1 - e, 3)) / ( $2 * power($3, 3))
             FROM (SELECT unnest($4) e ) x'
    INTO sk
    USING a, c, s, in_array;

    RETURN sk;
END;
$$ language plpgsql IMMUTABLE;
