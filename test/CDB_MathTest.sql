
SELECT cdb_math_mode(a) from unnest(ARRAY[1,2,2,3]) a;
SELECT cdb_math_mode(a) from unnest(ARRAY[1,2,3]) a;
SELECT cdb_math_mode(a) from unnest(ARRAY[1]) a;
