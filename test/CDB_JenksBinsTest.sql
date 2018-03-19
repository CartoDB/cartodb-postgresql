WITH data AS (
    SELECT Array[0.99, 1.0, 1.01,
                 4.99, 5.01,
                 10.01, 10.01,
                 15.01, 14.99,
                 20.1, 19.9]::numeric[] AS s
)
-- expectation is: 1, 5, 10, 15, 20
-- TODO: fix cdb_jenksbins to match ^^
SELECT round(unnest(CDB_JenksBins(s, 5))) FROM data;

WITH data_nulls AS (
    SELECT Array[0.99, 1.0, 1.01,
                 4.99, 5.01,
                 null, null,
                 10.01, 10.01,
                 15.01, 14.99,
                 null, null,
                 20.1, 19.9]::numeric[] AS s
)
-- expectation is: 1, 5, 10, 15, 20
-- TODO: fix cdb_jenksbins to match ^^
SELECT round(unnest(CDB_JenksBins(s, 5))) FROM data_nulls;
