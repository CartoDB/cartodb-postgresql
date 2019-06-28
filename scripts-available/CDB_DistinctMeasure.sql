--
-- CDB_DistinctMeasure 
--     calculates the fraction of rows in the 10 most common distinct categories
--     returns true if the number of rows in these 10 categories is >= 0.9 * total number of rows
-- 
-- 

CREATE OR REPLACE FUNCTION @extschema@.CDB_DistinctMeasure ( in_array text[], threshold numeric DEFAULT null ) RETURNS numeric as $$
DECLARE
    element_count INT4;
    maxval numeric;
    passes numeric;
BEGIN
    SELECT count(e) INTO element_count FROM ( SELECT unnest(in_array) e ) x;

    -- count number of occurrences per bin
    -- calculate the normalized cumulative sum
    -- return the max value: which corresponds nth entry 
    -- for n <= 10 depending on # of distinct values
    EXECUTE 'WITH a As (
              SELECT
                count(*) cnt
              FROM
                (SELECT * FROM unnest($2) e ) x
              WHERE e is not null
              GROUP BY e
              ORDER BY cnt DESC
            ),
            b As (
              SELECT
                sum(cnt) OVER (ORDER BY cnt DESC) / $1 As cumsum
              FROM a
              LIMIT 10
            )
            SELECT max(cumsum) maxval FROM b'
            INTO maxval
            USING element_count, in_array;
    IF threshold is null THEN
        passes = maxval;
    ELSE
        passes = CASE WHEN (maxval >= threshold) THEN 1 ELSE 0 END;
    END IF;

    RETURN passes;
END;
$$ language plpgsql IMMUTABLE PARALLEL SAFE;
