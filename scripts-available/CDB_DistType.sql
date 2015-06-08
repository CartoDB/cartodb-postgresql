--
-- CDB_DistType classifies the histograms of a column into
-- one of the basic types listed by Galtong: http://druedin.com/2012/12/08/galtungs-ajus-system/
-- 
-- Future improvements:
--    variable number of bins (7 is baked in right now)
--    catch the number of items to ensure that the sample is large enough
--
-- Refs:
--    1. width_bucket/histograms: http://tapoueh.org/blog/2014/02/21-PostgreSQL-histogram
--    2. R implementation: https://github.com/cran/agrmt

CREATE OR REPLACE FUNCTION CDB_DistType ( in_array NUMERIC[] ) RETURNS text as $$
DECLARE
    element_count INT4;
    minv numeric;
    maxv numeric;
    bins numeric[];
    freqs numeric[];
    ajus INT[];
    freq INT4;
    signature text;
    i INT := 1;
BEGIN
    SELECT min(e), max(e), count(e) INTO minv, maxv, element_count FROM ( SELECT unnest(in_array) e ) x;

    IF abs(maxv - minv) < 1e-7 THEN -- if max and min are nearly equal, call if 'F' (make relative to maxv?)
        signature = 'F';
    ELSE
        -- Calculate bins and count in bins
        EXECUTE 'WITH stats as (
            SELECT min(e) as minv,
                   max(e) as maxv,
                   count(e) as total
            FROM (SELECT unnest($1) e) x
            WHERE e is not null
        ),
        hist as (
            SELECT width_bucket(e, s.minv, s.maxv, 7) bucket,
                   count(*) freq
            FROM (SELECT unnest($1) e) x, stats s
            WHERE e is not null
            GROUP BY 1
            ORDER BY 1
        )
        SELECT array_agg(round(100.0 * hist.freq::numeric / stats.total::numeric,1)) freqs,
               array_agg(hist.bucket) buckets
        FROM hist, stats'
        INTO freqs, bins
        USING in_array;

        LOOP
            IF i < 7 THEN
                ajus[i] = CDB_CompareValues(freqs[i],freqs[i+1],5.0); -- 5% tolerance
            ELSE
                EXIT;
            END IF;
            i := i + 1;
        END LOOP;

        signature = CDB_DistributionType(ajus);
    END IF;

    RETURN signature;
END;
$$ language plpgsql IMMUTABLE;

-- Classify data into AJUSFL

CREATE OR REPLACE FUNCTION CDB_DistributionType ( in_array INT[] ) RETURNS text as $$
DECLARE
    element_count INT4;
    maxv numeric;
    minv numeric;
    uniques INT[];
    type text;
BEGIN
    SELECT max(e), min(e) INTO maxv, minv FROM ( SELECT unnest(in_array) e ) x;

    IF (maxv = 0 AND minv = 0) THEN
        type = 'F';
    ELSIF maxv < 1 THEN
        type = 'L';
    ELSIF minv > -1 THEN
        type = 'J';
    ELSE
        -- Get distinct elements ordered by original position
        EXECUTE 'WITH b AS (
            SELECT a
            FROM (SELECT unnest($1) a) x
        ),
        c AS (
            SELECT a, row_number() OVER () r
            FROM b
        ),
        d AS (
            SELECT DISTINCT a
            FROM c
        ),
        e AS (
            SELECT a FROM d ORDER BY (
                SELECT r FROM c WHERE d.a = c.a ORDER BY r ASC LIMIT 1
            ) ASC)
        SELECT array_agg(a) FROM e'
        INTO uniques
        USING in_array;

        -- Decide if it's an A, U, or other
        IF (uniques = ARRAY[1,-1] OR uniques = ARRAY[1,0,-1] OR uniques = ARRAY[1,-1,0] OR uniques = ARRAY[0,1,-1]) THEN
            type = 'A';
        ELSIF (uniques = ARRAY[-1,1] OR uniques = ARRAY[-1,0,1] OR uniques = ARRAY[-1,1,0] OR uniques = ARRAY[0,-1,1]) THEN
            type = 'U';
        ELSE
            type = 'S';
        END IF;
    END IF;

    RETURN type;
END;
$$ language plpgsql IMMUTABLE;

CREATE OR REPLACE FUNCTION CDB_CompareValues ( a numeric, b numeric, tolerance numeric ) RETURNS INT as $$
DECLARE
    d INT4;
BEGIN
    IF a > b THEN
        SELECT -1 INTO d;
    ELSE
        SELECT 1 INTO d;
    END IF;

    IF abs(a-b) <= tolerance THEN
        SELECT 0 INTO d;
    END IF;

    RETURN d;
END; 
$$ language plpgsql IMMUTABLE;
