SET client_min_messages TO error;
\set VERBOSITY terse

CREATE OR REPLACE FUNCTION CDB_CartodbfyTableCheck(tabname regclass, label text)
RETURNS text AS
$$
DECLARE
  sql TEXT;
  id INTEGER;
  rec RECORD;
  lag INTERVAL;
  tmp INTEGER;
  ogc_geom geometry_columns; -- old the_geom record in geometry_columns
  ogc_merc geometry_columns; -- old the_geom_webmercator record in geometry_columns
  tabtext TEXT;
BEGIN

  -- Save current constraints on geometry columns, if any
  ogc_geom = ('','','','',0,0,'GEOMETRY');
  ogc_merc = ogc_geom;
  sql := 'SELECT gc.* FROM geometry_columns gc, pg_class c, pg_namespace n '
    || 'WHERE c.oid = ' || tabname::oid || ' AND n.oid = c.relnamespace'
    || ' AND gc.f_table_schema = n.nspname AND gc.f_table_name = c.relname'
    || ' AND gc.f_geometry_column IN ( ' || quote_literal('the_geom')
    || ',' || quote_literal('the_geom_webmercator') || ')';
  FOR rec IN EXECUTE sql LOOP
    IF rec.f_geometry_column = 'the_geom' THEN
      ogc_geom := rec;
    ELSE
      ogc_merc := rec;
    END IF;
  END LOOP;

  tabtext := Format('%s.%s','public',tabname);
  RAISE NOTICE 'CARTODBFYING % !!!!', tabtext;
  PERFORM CDB_CartodbfyTable('public', tabname);
  tabname := tabtext::regclass;

  sql := 'INSERT INTO ' || tabname::text || '(the_geom) values ( CDB_LatLng(2,1) ) RETURNING cartodb_id';
  EXECUTE sql INTO STRICT id;
  sql := 'SELECT the_geom_webmercator FROM '
    || tabname::text || ' WHERE cartodb_id = ' || id;
  EXECUTE sql INTO STRICT rec;

  -- Check the_geom_webmercator trigger
  IF round(st_x(rec.the_geom_webmercator)) != 111319 THEN
    RAISE EXCEPTION 'the_geom_webmercator X is % (expecting 111319)', round(st_x(rec.the_geom_webmercator));
  END IF;
  IF round(st_y(rec.the_geom_webmercator)) != 222684 THEN
    RAISE EXCEPTION 'the_geom_webmercator Y is % (expecting 222684)', round(st_y(rec.the_geom_webmercator));
  END IF;

  -- Check CDB_TableMetadata entry
  sql := 'SELECT * FROM CDB_TableMetadata WHERE tabname = ' || tabname::oid;
  EXECUTE sql INTO STRICT rec;
  lag = rec.updated_at - now();
  IF lag > '1 second' THEN
    RAISE EXCEPTION 'updated_at in CDB_TableMetadata not set to now() after insert [ valued % ago ]', lag;
  END IF;

  -- Check geometry_columns entries
  tmp := 0;
  FOR rec IN
    SELECT
      CASE WHEN gc.f_geometry_column = 'the_geom' THEN 4326
           ELSE 3857 END as expsrid,
      CASE WHEN gc.f_geometry_column = 'the_geom' THEN ogc_geom.type
           ELSE ogc_merc.type END as exptype, gc.*
    FROM geometry_columns gc, pg_class c, pg_namespace n
    WHERE c.oid = tabname::oid AND n.oid = c.relnamespace
          AND gc.f_table_schema = n.nspname AND gc.f_table_name = c.relname
          AND gc.f_geometry_column IN ( 'the_geom', 'the_geom_webmercator')
  LOOP
    tmp := tmp + 1;
    -- Check SRID constraint
    IF rec.srid != rec.expsrid THEN
      RAISE EXCEPTION 'SRID of % in geometry_columns is %, expected %',
        rec.f_geometry_column, rec.srid, rec.expsrid;
    END IF;
    -- Check TYPE constraint didn't change
    IF (rec.type != 'GEOMETRY') AND (rec.type != 'POINT') THEN
      RAISE EXCEPTION 'type of % in geometry_columns is %, expected %',
        rec.f_geometry_column, rec.type, rec.exptype;
    END IF;
    -- check coord_dimension ?
  END LOOP;
  IF tmp != 2 THEN
      RAISE EXCEPTION '% entries found for table % in geometry_columns, expected 2', tmp, tabname;
  END IF;

  -- Check GiST index
  sql := 'SELECT a.attname, count(ri.relname) FROM'
    || ' pg_index i, pg_class c, pg_class ri, pg_attribute a, pg_opclass o'
    || ' WHERE i.indrelid = c.oid AND ri.oid = i.indexrelid'
    || ' AND a.attrelid = ri.oid AND o.oid = i.indclass[0]'
    || ' AND a.attname IN ( ' || quote_literal('the_geom')
    || ',' || quote_literal('the_geom_webmercator') || ')'
    || ' AND ri.relnatts = 1 AND o.opcname = '
    || quote_literal('gist_geometry_ops_2d')
    || ' AND c.oid = ' || tabname::oid
    || ' GROUP BY a.attname';
  RAISE NOTICE 'sql: %', sql;
  EXECUTE sql;
  GET DIAGNOSTICS tmp = ROW_COUNT;
  IF tmp != 2 THEN
      RAISE EXCEPTION '% gist indices found on the_geom and the_geom_webmercator, expected 2', tmp;
  END IF;

  -- Check null constraint on cartodb_id, created_at, updated_at
  SELECT count(*) FROM pg_attribute a, pg_class c WHERE c.oid = tabname::oid
    AND a.attrelid = c.oid AND NOT a.attisdropped AND a.attname in
      ( 'cartodb_id' )
    AND NOT a.attnotnull INTO strict tmp;
  IF tmp > 0 THEN
      RAISE EXCEPTION 'cartodb_id is missing not-null constraint';
  END IF;

  -- Cleanup
  sql := 'DELETE FROM ' || tabname::text || ' WHERE cartodb_id = ' || id;
  EXECUTE sql;

  RETURN label || ' cartodbfied fine';
END;
$$
LANGUAGE 'plpgsql';

-- check cartodbfytable idempotence
CREATE TABLE t AS SELECT 1::int as a;
SELECT CDB_CartodbfyTable('public', 't'); -- should fail
SELECT CDB_SetUserQuotaInBytes(0); -- Set user quota to infinite
SELECT CDB_CartodbfyTableCheck('t', 'single non-geometrical column');
DROP TABLE t;

-- table with single non-geometrical column
CREATE TABLE t AS SELECT ST_SetSRID(ST_MakePoint(-1,-1),4326) as the_geom, 1::int as cartodb_id, 'this is a sentence' as description;
SELECT CDB_CartodbfyTableCheck('t', 'check function idempotence');
SELECT * FROM t;
SELECT CDB_CartodbfyTableCheck('t', 'check function idempotence');
SELECT * FROM t;
DROP TABLE t;

-- table with existing srid-unconstrained (but type-constrained) the_geom
CREATE TABLE t AS SELECT ST_SetSRID(ST_MakePoint(0,0),4326)::geometry(point) as the_geom;
SELECT CDB_CartodbfyTableCheck('t', 'srid-unconstrained the_geom');
DROP TABLE t;

-- table with mixed-srid the_geom values
CREATE TABLE t AS SELECT ST_SetSRID(ST_MakePoint(-1,-1),4326) as the_geom
UNION ALL SELECT ST_SetSRID(ST_MakePoint(0,0),3857);
SELECT CDB_CartodbfyTableCheck('t', 'mixed-srid the_geom');
SELECT 'extent',ST_Extent(ST_SnapToGrid(the_geom,0.2)) FROM t;
DROP TABLE t;

-- table with wrong srid-constrained the_geom values
CREATE TABLE t AS SELECT 'SRID=3857;LINESTRING(222638.981586547 222684.208505545, 111319.490793274 111325.142866385)'::geometry(geometry,3857) as the_geom;
SELECT CDB_CartodbfyTableCheck('t', 'wrong srid-constrained the_geom');
SELECT 'extent',ST_Extent(ST_SnapToGrid(the_geom,0.2)),ST_Extent(ST_SnapToGrid(the_geom_webmercator,1)) FROM t;
DROP TABLE t;

-- table with wrong srid-constrained the_geom_webmercator values (and no the_geom!)
CREATE TABLE t AS SELECT 'SRID=4326;LINESTRING(1 1,2 2)'::geometry(geometry,4326) as the_geom_webmercator;
SELECT CDB_CartodbfyTableCheck('t', 'wrong srid-constrained the_geom_webmercator');
-- expect the_geom to be populated from the_geom_webmercator
SELECT 'extent',ST_Extent(ST_SnapToGrid(the_geom,0.2)) FROM t;
DROP TABLE t;

-- table with existing triggered the_geom
CREATE TABLE t AS SELECT 'SRID=4326;LINESTRING(1 1,2 2)'::geometry(geometry) as the_geom;
CREATE TRIGGER update_the_geom_webmercator_trigger BEFORE UPDATE OF the_geom ON t
 FOR EACH ROW EXECUTE PROCEDURE _CDB_update_the_geom_webmercator();
SELECT CDB_CartodbfyTableCheck('t', 'trigger-protected the_geom');
SELECT 'extent',ST_Extent(ST_SnapToGrid(the_geom,0.2)) FROM t;
DROP TABLE t;

-- table with existing cartodb_id field of type text
CREATE TABLE t AS SELECT 10::text as cartodb_id;
SELECT CDB_CartodbfyTableCheck('t', 'text cartodb_id');
select cartodb_id/2 FROM t;
DROP TABLE t;

-- table with existing cartodb_id field of type text not casting
CREATE TABLE t AS SELECT 'nan'::text as cartodb_id;
SELECT CDB_CartodbfyTableCheck('t', 'uncasting text cartodb_id');
DROP TABLE t;

-- table with empty cartodb_id field of type text
CREATE TABLE t AS SELECT null::text as cartodb_id;
SELECT CDB_CartodbfyTableCheck('t', 'empty text cartodb_id');
SELECT cartodb_id from t;
DROP TABLE t;

-- table with existing cartodb_id field of type int4 not sequenced
CREATE TABLE t AS SELECT 1::int4 as cartodb_id;
SELECT CDB_CartodbfyTableCheck('t', 'unsequenced cartodb_id');
SELECT cartodb_id FROM t;
DROP TABLE t;

-- table with text geometry column
CREATE TABLE t AS SELECT 'SRID=4326;POINT(1 1)'::text AS the_geom, 1::int4 as cartodb_id;
SELECT CDB_CartodbfyTableCheck('t', 'text the_geom column');
SELECT cartodb_id FROM t;
DROP TABLE t;

-- table with text geometry column, no SRS
CREATE TABLE t AS SELECT 'POINT(1 1)'::text AS the_geom, 1::int4 as cartodb_id;
SELECT CDB_CartodbfyTableCheck('t', 'text the_geom column, no srs');
SELECT cartodb_id FROM t;
DROP TABLE t;

-- table with text geometry column, unusual SRS
CREATE TABLE t AS SELECT 'SRID=26910;POINT(1 1)'::text AS the_geom, 1::int4 as cartodb_id;
SELECT CDB_CartodbfyTableCheck('t', 'text the_geom column, srs = 26819');
SELECT cartodb_id FROM t;
DROP TABLE t;

-- table with text unparseable geometry column
CREATE TABLE t AS SELECT 'SRID=26910;PONT(1 1)'::text AS the_geom, 1::int4 as cartodb_id;
SELECT CDB_CartodbfyTableCheck('t', 'text the_geom column, unparseable content');
SELECT cartodb_id FROM t;
DROP TABLE t;

-- table with existing cartodb_id serial primary key
CREATE TABLE t ( cartodb_id serial primary key );
SELECT CDB_CartodbfyTableCheck('t', 'cartodb_id serial primary key');
SELECT c.conname, a.attname FROM pg_constraint c, pg_attribute a
WHERE c.conrelid = 't'::regclass and a.attrelid = c.conrelid
AND c.conkey[1] = a.attnum AND NOT a.attisdropped;
DROP TABLE t;

-- tables can be renamed and there's no index name clashing #123
CREATE TABLE original();
SELECT CDB_CartodbfyTable('original');
ALTER TABLE original RENAME TO original_renamed;
CREATE TABLE original();
SELECT CDB_CartodbfyTable('original');
DROP TABLE original_renamed;
DROP TABLE original;

-- Table always have a default seq value after cartodbfy #138
CREATE TABLE bug_empty_table_no_seq (
  cartodb_id integer,
  the_geom geometry(Geometry,4326),
  the_geom_webmercator geometry(Geometry,3857),
  name text,
  description text
);
SELECT CDB_CartodbfyTableCheck('bug_empty_table_no_seq', 'Table always have a default seq value after cartodbfy #138');
INSERT INTO bug_empty_table_no_seq DEFAULT VALUES;
DROP TABLE bug_empty_table_no_seq;

-- Existing cartodb_id values are respected
CREATE table existing_cartodb_id (
  cartodb_id integer,
  the_geom geometry(Geometry,4326),
  the_geom_webmercator geometry(Geometry,3857),
  name text,
  description text
);
INSERT INTO existing_cartodb_id (cartodb_id, description) VALUES
       (10, 'a'),
       (20, 'b'),
       (30, 'c');
SELECT CDB_CartodbfyTableCheck('existing_cartodb_id', 'Existing cartodb_id values are respected #138');
SELECT cartodb_id,the_geom,the_geom_webmercator,description,name from existing_cartodb_id;
DROP TABLE existing_cartodb_id;

-- Table with both the_geom and wkb_geometry
CREATE TABLE many_geometry_columns (
       the_geom geometry,
       wkb_geometry geometry(MultiPoint,4326),
       description varchar
);
INSERT INTO many_geometry_columns (the_geom, wkb_geometry) VALUES
       ('0104000020E61000000100000001010000007108B023698052C03CEEA53A2E5D4440', '0104000020E61000000100000001010000007108B023698052C03CEEA53A2E5D4440'),
       ('0104000020E6100000010000000101000000864C9E57618052C0994F0C7F3C5B4440', '0104000020E6100000010000000101000000864C9E57618052C0994F0C7F3C5B4440');
SELECT CDB_CartodbfyTableCheck('many_geometry_columns', 'Table with both the_geom and wkb_geometry #141');
SELECT * FROM many_geometry_columns;
DROP TABLE many_geometry_columns;

-- Many colliding geom columns
CREATE TABLE many_colliding_columns (
  the_geom varchar,
  the_geom_webmercator varchar,
  my_geom geometry,
  my_mercgeom geometry(Point, 3857),
  cartodb_id varchar,
  my_pk integer primary key
);
INSERT INTO many_colliding_columns VALUES (
 'foo', 'bar', 'SRID=4326;POINT(0 0)', 'SRID=3857;POINT(0 0)', 'nerf', 1
);
SELECT CDB_CartodbfyTableCheck('many_colliding_columns', 'Many colliding columns #141');
DROP TABLE many_colliding_columns;

-- Table with null cartodb_id
CREATE TABLE test (
  cartodb_id integer
);
INSERT INTO test VALUES
  (1),
  (2),
  (NULL),
  (3);
SELECT CDB_CartodbfyTableCheck('test', 'Table with null cartodb_id #148');
SELECT cartodb_id from test;
DROP TABLE test;

-- Table with non unique cartodb_id
CREATE TABLE test (
  cartodb_id integer
);
INSERT INTO test VALUES
  (1),
  (2),
  (2);
SELECT CDB_CartodbfyTableCheck('test', 'Table with non unique cartodb_id #148');
SELECT cartodb_id from test;
DROP TABLE test;

-- Table with non unique and null cartodb_id
CREATE TABLE test (
  cartodb_id integer
);
INSERT INTO test VALUES
  (1),
  (2),
  (NULL),
  (2);
SELECT CDB_CartodbfyTableCheck('test', 'Table with non unique and null cartodb_id #148');
SELECT cartodb_id from test;
DROP TABLE test;

CREATE TABLE test (
  cartodb_id integer
);
CREATE UNIQUE INDEX "test_cartodb_id_key" ON test (cartodb_id);
CREATE UNIQUE INDEX "test_cartodb_id_pkey" ON test (cartodb_id);
ALTER TABLE test ADD CONSTRAINT "test_pkey" PRIMARY KEY USING INDEX test_cartodb_id_pkey;
INSERT INTO test VALUES
  (1),
  (2),
  (3);
SELECT CDB_CartodbfyTableCheck('test', 'Table with primary key and unique index on it #174');
SELECT cartodb_id from test;
DROP TABLE test;

CREATE TABLE test (
  name varchar,
  "first.value" integer,
  "second.value" integer
);
INSERT INTO test VALUES ('one', 1, 2), ('two', 3, 4);
SELECT CDB_CartodbfyTableCheck('test', 'Table with dots in name columns (cartodb #6114)');
SELECT name, "first.value" from test;
DROP TABLE test;

SET client_min_messages TO notice;
-- _CDB_create_cartodb_id_column with cartodb_id integer already present
CREATE TABLE test (cartodb_id integer);

SELECT _CDB_Create_Cartodb_ID_Column('test'::regclass);
SELECT column_name FROM information_schema.columns WHERE table_name = 'test' AND column_name = '_cartodb_id0';

DROP TABLE test;

-- _CDB_create_cartodb_id_column with cartodb_id text already present
CREATE TABLE test (cartodb_id text);

SELECT _CDB_Create_Cartodb_ID_Column('test'::regclass);
SELECT column_name FROM information_schema.columns WHERE table_name = 'test' AND column_name = '_cartodb_id0';

DROP TABLE test;
SET client_min_messages TO error;

-- Unique identifier generation can break CDB_CartodbfyTable #305
BEGIN;
    DO $$
    BEGIN
       FOR i IN 1..150 LOOP
            EXECUTE 'CREATE TABLE untitled_table();';
            EXECUTE $query$SELECT CDB_CartodbfyTable('untitled_table');$query$;
            EXECUTE 'ALTER TABLE untitled_table RENAME TO my_renamed_table_' || i;
       END LOOP;
    END;
    $$;
ROLLBACK;

-- Long table name could cause possible sequence rename collision #325
CREATE TABLE "wadus_table_9473e8f6-2da1-11e8-8bca-0204e4dfe4d8" ( cartodb_id serial primary key );
SELECT CDB_CartodbfyTableCheck('wadus_table_9473e8f6-2da1-11e8-8bca-0204e4dfe4d8'::REGCLASS, 'Long table name could cause sequence collision while renaming #325');
DROP TABLE "wadus_table_9473e8f6-2da1-11e8-8bca-0204e4dfe4d8";

-- TODO: table with existing custom-triggered the_geom

DROP FUNCTION CDB_CartodbfyTableCheck(regclass, text);
DROP FUNCTION _CDB_UserQuotaInBytes();
