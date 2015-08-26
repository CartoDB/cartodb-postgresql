--
-- Calculate the Pearson kurtosis of the input data
--
-- @param in_array A numeric array of numbers to determine the best
--                   to determine the bin boundary
--
-- @param breaks The number of bins you want to find.
--  
--
-- Returns: upper edges of bins
-- 
--

CREATE OR REPLACE FUNCTION CDB_Kurtosis ( in_array NUMERIC[] ) RETURNS NUMERIC as $$
DECLARE 
    a numeric;
    c numeric;
    s numeric;
    k numeric;
BEGIN
    SELECT AVG(e), COUNT(e)::numeric, stddev(e) INTO a, c, s FROM ( SELECT unnest(in_array) e ) x;

    RAISE NOTICE 'avg: %, cnt: %, std: %', a, c, s;

    EXECUTE '
        SELECT sum(power($1 - e,4)) / ( $2 * power($3, 4))
        FROM (SELECT unnest($4) e ) x'
    INTO k
    USING a, c, s, in_array;

    RETURN k;
END;
$$ language plpgsql IMMUTABLE;
