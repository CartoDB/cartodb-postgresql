WITH data AS (
    SELECT Array[0.99, 1.0, 1.01,
                 4.99, 5.01,
                 10.01, 10.01,
                 15.01, 14.99,
                 20.1, 19.9]::numeric[] AS s
)
SELECT unnest(CDB_JenksBins(s, 5)) FROM data;


WITH data_nulls AS (
    SELECT Array[0.99, 1.0, 1.01,
                 4.99, 5.01,
                 null, null,
                 10.01, 10.01,
                 15.01, 14.99,
                 null, null,
                 20.1, 19.9]::numeric[] AS s
)
SELECT unnest(CDB_JenksBins(s, 5)) FROM data_nulls;


WITH data_inverse AS (
    SELECT Array[0.99, 1.0, 1.01,
                 4.99, 5.01,
                 10.01, 10.01,
                 15.01, 14.99,
                 20.1, 19.9]::numeric[] AS s
)
SELECT unnest(CDB_JenksBins(s, 5, 0, true)) FROM data_inverse;


WITH data_small AS (
    SELECT Array[0.99, 1.0, 10.01, 10.01, 10.01, 10.01]::numeric[] AS s
)
SELECT unnest(CDB_JenksBins(s, 4)) FROM data_small;
