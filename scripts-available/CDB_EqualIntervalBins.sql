--
-- Calculate the equal interval bins for a given column
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

CREATE OR REPLACE FUNCTION CDB_EqualIntervalBins ( in_array NUMERIC[], breaks INT) RETURNS NUMERIC[] as $$ 
DECLARE 
    diff numeric;
    min_val numeric;
    tmp_val numeric;
    i INT := 1;
    reply numeric[];
BEGIN
    SELECT (max(e) - min(e)) / breaks::numeric, min(e) INTO diff, min_val FROM (SELECT unnest(in_array) e) x WHERE e is not null;
    RAISE NOTICE 'diff = %, min_val = %', diff, min_val;
    LOOP
        IF i < breaks + 1 THEN
            tmp_val = min_val + i::numeric * diff;
            RAISE NOTICE 'tmp_val = %', tmp_val;
            reply = array_append(reply, tmp_val);
            i := i+1;
        ELSE
            EXIT;
        END IF;
    END LOOP;
    RETURN reply;
END; 
$$ language plpgsql IMMUTABLE;
