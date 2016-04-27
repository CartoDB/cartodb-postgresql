WITH data AS (
    SELECT array_agg(x::numeric) x FROM generate_series(1,100) x
        WHERE x % 5 != 0 AND x % 7 != 0
    )
SELECT unnest(CDB_QuantileBins(x, 7)) FROM data;

WITH data_nulls AS (
    SELECT array_agg(CASE WHEN x % 4 != 0 THEN x ELSE NULL END) x FROM generate_series(1,100) x
        WHERE x % 5 != 0 AND x % 7 != 0
    )
SELECT unnest(CDB_QuantileBins(x, 7)) FROM data_nulls;
