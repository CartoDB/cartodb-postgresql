-- Check small grids are generated...
SELECT COUNT(*) FROM cartodb.CDB_RectangleGrid(ST_MakeEnvelope(0,0,1000,1000,3857), 10, 10);

-- But large grids produce an error
SELECT COUNT(*) FROM cartodb.CDB_RectangleGrid(ST_MakeEnvelope(0,0,1000,1000,3857), 1, 1);
