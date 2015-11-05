WITH a AS (SELECT (CDB_SunCalc_GetTimes('2013-03-05UTC'::timestamptz, CDB_LatLng(50.5,30.5))).*)
SELECT name, round(DATE_PART('epoch', time)) epoch FROM a ORDER BY name ASC