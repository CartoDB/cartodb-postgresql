--
-- Set of functions to derive Sun locations and key times of day for any
-- location and time of year on earth
--
-- Primary functions are 
-- CDB_SunCalc_GetPosition(date TIMESTAMPTZ, coord GEOMETRY)
-- and 
-- CDB_SunCalc_GetTimes(date TIMESTAMPTZ, coord GEOMETRY)
--
-- To see the current sun location for NYC run
-- SELECT (CDB_SunCalc_GetPosition(now(), CDB_LatLng(40.7127, -74.0059))).*
--
-- To see the named moments of the day in NYC today run
-- SELECT (CDB_SunCalc_GetTimes(now(), CDB_LatLng(40.7127, -74.0059))).*
--
-- Derived from work done in SunCalc.js
-- SunCalc.js is available here https://github.com/mourner/suncalc
-- Original SunCalc License https://github.com/mourner/suncalc/blob/master/LICENSE
--


-- {
-- Create custome types needed by _CDB_SunCalc_
-- }{
CREATE TYPE _cdb_suncalc_position AS (
  azimuth decimal,
  altitude decimal
);
CREATE TYPE _cdb_suncalc_coords AS (
  declination decimal,
  rightAscension decimal
);
CREATE TYPE _cdb_suncalc_positions AS (
  name text,
  time timestamptz
);
-- }

-- {
-- Return Julian date from Timestamp With Timezone
-- }{
CREATE OR REPLACE FUNCTION _CDB_SunCalc_ToJulian(date TIMESTAMPTZ) RETURNS numeric as $$ 
DECLARE
    dayMs NUMERIC = 60 * 60 * 24;
    J1970 NUMERIC = 2440588;
    J2000 NUMERIC = 2451545;
BEGIN 
  RETURN (EXTRACT(EPOCH FROM date)) / dayMs  - 0.5 + J1970;
END; 
$$ language plpgsql IMMUTABLE;
-- }

-- {
-- Returns a Timestamp With Timezone from Julian date
--
-- }{
CREATE OR REPLACE FUNCTION _CDB_SunCalc_FromJulian(j NUMERIC) RETURNS timestamptz as $$ 
DECLARE
    dayMs NUMERIC = 60 * 60 * 24;
    J1970 NUMERIC = 2440588;
    J2000 NUMERIC = 2451545;
BEGIN 
    RETURN TIMESTAMP WITH TIME ZONE 'epoch' + (j + 0.5 - J1970) * dayMs * INTERVAL '1 second';
END; 
$$ language plpgsql IMMUTABLE;
-- }

-- {
-- Returns numeric Julian days from timestamp with timezone
--
-- }{
CREATE OR REPLACE FUNCTION _CDB_SunCalc_ToDays(date TIMESTAMPTZ) RETURNS NUMERIC as $$ 
DECLARE
    dayMs NUMERIC = 60 * 60 * 24;
    J1970 NUMERIC = 2440588;
    J2000 NUMERIC = 2451545;
BEGIN 
    RETURN _CDB_SunCalc_ToJulian(date) - J2000;
END; 
$$ language plpgsql IMMUTABLE;
-- }

-- {
-- A set of utlitiy functions for SunCalc calculations
-- }{

CREATE OR REPLACE FUNCTION _CDB_SunCalc_RightAscension(l NUMERIC, b NUMERIC) RETURNS NUMERIC as $$ 
DECLARE
    rad NUMERIC = pi() / 180.0;
    e NUMERIC = rad * 23.4397; 
BEGIN 
    RETURN atan2(sin(l) * cos(e) - tan(b) * sin(e), cos(l));
END; 
$$ language plpgsql IMMUTABLE;


CREATE OR REPLACE FUNCTION _CDB_SunCalc_Declination(l NUMERIC, b NUMERIC) RETURNS NUMERIC as $$ 
DECLARE
    rad NUMERIC = pi() / 180.0;
    e NUMERIC = rad * 23.4397; 
BEGIN 
    RETURN asin(sin(b) * cos(e) + cos(b) * sin(e) * sin(l));
END; 
$$ language plpgsql IMMUTABLE;


CREATE OR REPLACE FUNCTION _CDB_SunCalc_Azimuth(H NUMERIC, phi NUMERIC, deci NUMERIC) RETURNS NUMERIC as $$ 
BEGIN 
    RETURN atan2(sin(H), cos(H) * sin(phi) - tan(deci) * cos(phi));
END; 
$$ language plpgsql IMMUTABLE;


CREATE OR REPLACE FUNCTION _CDB_SunCalc_Altitude(H NUMERIC, phi NUMERIC, deci NUMERIC) RETURNS NUMERIC as $$ 
BEGIN 
    RETURN asin(sin(phi) * sin(deci) + cos(phi) * cos(deci) * cos(H));
END; 
$$ language plpgsql IMMUTABLE;


CREATE OR REPLACE FUNCTION _CDB_SunCalc_SiderealTime(d NUMERIC, lw NUMERIC) RETURNS NUMERIC as $$ 
DECLARE
    rad NUMERIC = pi() / 180.0;
BEGIN 
    RETURN rad * (280.16 + 360.9856235 * d) - lw;
END; 
$$ language plpgsql IMMUTABLE;


CREATE OR REPLACE FUNCTION _CDB_SunCalc_SolarMeanAnomaly(d NUMERIC) RETURNS NUMERIC as $$ 
DECLARE
    rad NUMERIC = pi() / 180.0;
BEGIN 
    RETURN rad * (357.5291 + 0.98560028 * d);
END; 
$$ language plpgsql IMMUTABLE;


CREATE OR REPLACE FUNCTION _CDB_SunCalc_EclipticLongitude(M NUMERIC) RETURNS NUMERIC as $$ 
DECLARE
    rad NUMERIC = pi() / 180.0;
    c NUMERIC;
    p NUMERIC;
BEGIN 
    c = rad * (1.9148 * sin(M) + 0.02 * sin(2 * M) + 0.0003 * sin(3 * M));
    p = rad * 102.9372;
    RETURN M + c + p + pi();
END; 
$$ language plpgsql IMMUTABLE;


CREATE OR REPLACE FUNCTION _CDB_SunCalc_SunCoords(d NUMERIC) RETURNS _cdb_suncalc_coords as $$ 
DECLARE
    m NUMERIC;
    l NUMERIC;
BEGIN 
    m = _CDB_SunCalc_SolarMeanAnomaly(d);
    l = _CDB_SunCalc_EclipticLongitude(M);
    -- Returns (dec, ra)
    RETURN (_CDB_SunCalc_Declination(L, 0), _CDB_SunCalc_RightAscension(L, 0));
END; 
$$ language plpgsql IMMUTABLE;


CREATE OR REPLACE FUNCTION _CDB_SunCalc_julianCycle(d NUMERIC, lw NUMERIC) RETURNS NUMERIC as $$ 
DECLARE
    jO NUMERIC = 0.0009;
BEGIN 
    RETURN round(d - jO - lw / (2 * pi()));
END; 
$$ language plpgsql IMMUTABLE;


CREATE OR REPLACE FUNCTION _CDB_SunCalc_approxTransit(Ht NUMERIC, lw NUMERIC, n NUMERIC) RETURNS NUMERIC as $$ 
DECLARE
    jO NUMERIC = 0.0009;
BEGIN 
    RETURN jO + (Ht + lw) / (2 * pi()) + n;
END; 
$$ language plpgsql IMMUTABLE;


CREATE OR REPLACE FUNCTION _CDB_SunCalc_solarTransitJ(ds NUMERIC, M NUMERIC, L NUMERIC) RETURNS NUMERIC as $$ 
DECLARE
    jO NUMERIC = 0.0009;
    J2000 NUMERIC = 2451545;
BEGIN 
    RETURN J2000 + ds + 0.0053 * sin(M) - 0.0069 * sin(2 * L);
END; 
$$ language plpgsql IMMUTABLE;


CREATE OR REPLACE FUNCTION _CDB_SunCalc_hourAngle(h NUMERIC, phi NUMERIC, d NUMERIC) RETURNS NUMERIC as $$ 
BEGIN 
    RETURN acos((sin(h) - sin(phi) * sin(d)) / (cos(phi) * cos(d)));
END; 
$$ language plpgsql IMMUTABLE;


CREATE OR REPLACE FUNCTION _CDB_SunCalc_getSetJ(h NUMERIC, lw NUMERIC, phi NUMERIC, deci NUMERIC, n NUMERIC, M NUMERIC, L NUMERIC) RETURNS NUMERIC as $$ 
DECLARE
    w NUMERIC;
    a NUMERIC;
BEGIN 
    w = _CDB_SunCalc_hourAngle(h, phi, deci);
    a = _CDB_SunCalc_approxTransit(w, lw, n);
    RETURN _CDB_SunCalc_solarTransitJ(a, M, L);
END; 
$$ language plpgsql IMMUTABLE;
-- }

-- {
-- Returns the Azimuth and Altitude of the sun in the sky for any 
--
-- Timestamp With Timezone and Geometry in 4326
--
-- }{
CREATE OR REPLACE FUNCTION CDB_SunCalc_GetPosition(date TIMESTAMPTZ, coord GEOMETRY) RETURNS _cdb_suncalc_position as $$ 
DECLARE
    rad NUMERIC = pi() / 180.0;
    lw NUMERIC;
    phi NUMERIC;
    d NUMERIC;
    c _cdb_suncalc_coords;
    h NUMERIC;
    azimuth NUMERIC;
    altitude NUMERIC;
BEGIN 
    coord := ST_Transform(coord, 4326);
    lw = rad * -1 * ST_X(coord);
    phi = rad * ST_Y(coord);
    d = _CDB_SunCalc_ToDays(date);
    c = _CDB_SunCalc_SunCoords(d);
    h = _CDB_SunCalc_SiderealTime(d, lw) - c.rightAscension;

    -- returns (azimuth, altitude)
    RETURN (_CDB_SunCalc_Azimuth(h, phi, c.declination), _CDB_SunCalc_Altitude(h, phi, c.declination) );
END; 
$$ language plpgsql IMMUTABLE;
-- }

-- {
-- Returns a set of textual descriptions of times of day by the timestamp with timezone 
--
-- input Timestamp With Timezone and Geometry in 4326
--
-- }{
CREATE OR REPLACE FUNCTION CDB_SunCalc_GetTimes(date TIMESTAMPTZ, coord GEOMETRY) RETURNS SETOF _cdb_suncalc_positions as $$ 
DECLARE
    rad NUMERIC = pi() / 180.0;
    lw NUMERIC;
    phi NUMERIC;
    d NUMERIC;
    n NUMERIC;
    ds NUMERIC;
    M NUMERIC;
    L NUMERIC;
    deci NUMERIC;
    Jnoon NUMERIC;
    i NUMERIC;
    len NUMERIC;
    tt NUMERIC;
    Jset NUMERIC;
    Jrise NUMERIC;
    degs NUMERIC[] = ARRAY[-0.833, -0.3, -6, -12, -18, 6];
    rises TEXT[] = ARRAY['sunrise','sunriseEnd','dawn','nauticalDawn','nightEnd','goldenHourEnd'];
    sets TEXT[] = ARRAY['sunset','sunsetStart','dusk','nauticalDusk','night','goldenHour'];
BEGIN 
    coord := ST_Transform(coord, 4326);
    lw = rad * -1 * ST_X(coord);
    phi = rad * ST_Y(coord);

    d = _CDB_SunCalc_ToDays(date);
    n = _CDB_SunCalc_JulianCycle(d, lw);
    ds = _CDB_SunCalc_ApproxTransit(0, lw, n);

    M = _CDB_SunCalc_SolarMeanAnomaly(ds);
    L = _CDB_SunCalc_EclipticLongitude(M);
    deci = _CDB_SunCalc_Declination(L, 0);

    Jnoon = _CDB_SunCalc_SolarTransitJ(ds, M, L);

    RETURN NEXT ('solarnoon'::text, _CDB_SunCalc_fromJulian(Jnoon));
    RETURN NEXT ('nadir'::text, _CDB_SunCalc_fromJulian(Jnoon - 0.5));
    FOR i IN 1 .. array_upper(degs, 1)
    LOOP
        Jset = _CDB_SunCalc_getSetJ(degs[i] * rad, lw, phi, deci, n, M, L);
        Jrise = Jnoon - (Jset - Jnoon);
        RETURN NEXT (rises[i], _CDB_SunCalc_fromJulian(Jrise));
        RETURN NEXT (sets[i], _CDB_SunCalc_fromJulian(Jset));
    END LOOP;
    RETURN; 
END; 
$$ language plpgsql IMMUTABLE;
-- }