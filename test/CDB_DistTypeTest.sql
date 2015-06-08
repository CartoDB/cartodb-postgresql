WITH data AS (
    SELECT pow(x,3)::numeric x FROM generate_series(-100,100) x
    ) 
SELECT CDB_DistType(array_agg(x)) FROM data
