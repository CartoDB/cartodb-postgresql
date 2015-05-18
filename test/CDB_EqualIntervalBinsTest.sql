WITH data AS (
    SELECT array_agg(x::numeric) s FROM generate_series(1,300) x 
        WHERE x % 5 != 0 AND x % 7 != 0
    ) 
SELECT round(unnest(CDB_EqualIntervalBins(s, 7)),7) FROM data