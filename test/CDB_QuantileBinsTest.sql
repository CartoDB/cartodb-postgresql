WITH data AS (
    SELECT array_agg(x::numeric) AS s
    FROM generate_series(0, 99) AS x
    ) 
SELECT unnest(CDB_QuantileBins(s, 10))
  FROM data;

WITH data_nulls AS (
    SELECT array_agg(x::numeric) AS s
      FROM (
        SELECT x FROM generate_series(0, 99) AS x
        UNION ALL
        SELECT null AS x FROM generate_series(1, 10) AS x
        ) _wrap
    )
SELECT unnest(CDB_QuantileBins(s, 10))
  FROM data_nulls;
