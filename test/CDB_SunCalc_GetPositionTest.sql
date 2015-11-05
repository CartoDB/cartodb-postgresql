WITH a AS (SELECT (CDB_SunCalc_GetPosition('2013-03-05UTC'::timestamptz, CDB_LatLng(50.5,30.5))).*)
SELECT round(altitude, 6) altitude, round(azimuth,6) FROM a
