--
-- Calculate logarithmic bins for a given column
--
-- @param in_array A numeric array of numbers to determine the best
--                   to determine the bin boundary
--
-- @param breaks The number of bins you want to find.
--
--
-- @param poi The point of interest. Available values: 'start', 'end', 'center', empty string for poi guessing (bucketed mode) and numerical value as string for arbitrary poi
--
--
-- Returns: upper edges of bins
--
--

CREATE OR REPLACE FUNCTION CDB_LogBins (in_array NUMERIC[], breaks INT, poi text ) RETURNS NUMERIC[] as $$
DECLARE
    min_val numeric;
    max_val numeric;
    tmp_val numeric;
    tmp_a numeric[];
    tmp_b numeric[];
    tmp_f numeric[];
    tmp_mf numeric;
    i INT := 1;
    logserie numeric[];
    reply numeric[];
BEGIN
    SELECT min(e), max(e) INTO min_val, max_val FROM ( SELECT unnest(in_array) e ) x WHERE e IS NOT NULL;
    IF poi = 'start' OR poi = 'end' THEN
        WHILE i < breaks+1 LOOP
            tmp_val := i * 100 / breaks;
            IF tmp_val <> 0.0 THEN
                tmp_val := log(tmp_val) * 50; -- 50 = 100/log(100)
            END IF;
            logserie := array_append(logserie, tmp_val);
            i := i+1;
        END LOOP;
        i:= 1;
        WHILE i < breaks + 1 LOOP
            IF poi='start' THEN
                if i = breaks THEN
                    tmp_val := max_val;
                ELSE
                    tmp_val := min_val + (100-logserie[breaks-i]) * (max_val - min_val) / 100.0;
                END IF;
            ELSE
                tmp_val := min_val + logserie[i]  * (max_val - min_val) / 100.0;
            END IF;
            reply := array_append(reply, tmp_val);
            i := i+1;
        END LOOP;
    ELSE
        IF poi = 'center' THEN
            poi := 0.5 * (max_val - min_val);
        ELSEIF poi='' THEN
            tmp_val := breaks-1;
            WITH a AS(
                SELECT unnest(in_array) e
            ),b AS(
                SELECT width_bucket(a.e, min_val, max_val, tmp_val::integer) AS bucket, count(*) AS freq, min(a.e)+0.5*(max(a.e) - min(a.e)) as avg FROM a where e is not null GROUP BY bucket ORDER BY bucket
            )
            SELECT array_agg(b.bucket), array_agg(b.avg), array_agg(b.freq), max(b.freq) INTO tmp_b, tmp_a, tmp_f, tmp_mf FROM b;
            i := 1;
            WHILE i < array_length(tmp_b,1) LOOP
                IF tmp_f[i]=tmp_mf THEN
                    poi := tmp_a[i]::text;
                    exit;
                END IF;
                i := i+1;
            END LOOP;
        END IF;
        WITH a AS(SELECT unnest(in_array ) e), b AS (SELECT array_agg(a.e) as m FROM a WHERE a.e<= poi::numeric), c AS(SELECT array_agg(a.e) as m FROM a WHERE a.e> poi::numeric) SELECT b.m, c.m INTO tmp_a, tmp_b FROM b,c;
        i := floor(breaks/2);
        IF breaks % 2 > 0 THEN
            i := i + 1;
        END IF;
        tmp_a := CDB_LogBins(tmp_a, i, 'end');
        tmp_b := CDB_LogBins(tmp_b, i, 'start');
        reply := tmp_a || tmp_b;
    END IF;
    RETURN reply;
END;
$$ language plpgsql IMMUTABLE;

