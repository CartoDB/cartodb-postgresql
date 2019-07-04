-- Setup: create and populate a table to test the syncs
\set QUIET on
BEGIN;
SET client_min_messages TO error;
CREATE TABLE test_sync_source (
  cartodb_id bigint,
  lat double precision,
  lon double precision,
  name text
);
INSERT INTO test_sync_source VALUES
  (1, 1.0, 1.0, 'foo'),
  (2, 2.0, 2.0, 'bar'),
  (3, 3.0, 3.0, 'patata'),
  (4, 4.0, 4.0, 'melon');
SET client_min_messages TO notice;
\set QUIET off


\echo 'First table sync: it should be simply just copied to the destination'
SELECT cartodb.CDB_SyncTable('test_sync_source', 'public', 'test_sync_dest');

\echo 'Next table sync: there shall be no changes'
SELECT cartodb.CDB_SyncTable('test_sync_source', 'public', 'test_sync_dest');

\echo 'Remove a row from the source and check it is deleted from the dest table'
DELETE FROM test_sync_source WHERE cartodb_id = 3;
SELECT cartodb.CDB_SyncTable('test_sync_source', 'public', 'test_sync_dest');

\echo 'Insert a new row and check that it is inserted in the dest table'
INSERT INTO test_sync_source VALUES (5, 5.0, 5.0, 'sandia');
SELECT cartodb.CDB_SyncTable('test_sync_source', 'public', 'test_sync_dest');

\echo 'Modify row and check that it is modified in the dest table'
UPDATE test_sync_source SET name = 'cantaloupe' WHERE cartodb_id = 4;
SELECT cartodb.CDB_SyncTable('test_sync_source', 'public', 'test_sync_dest');

\echo 'Sanity check: the end result is the same source table'
SELECT * FROM test_sync_source ORDER BY cartodb_id;
SELECT * FROM test_sync_dest ORDER BY cartodb_id;


\echo 'It shall exclude geom columns if instructed to do so'
\set QUIET on
SET client_min_messages TO error;
SELECT cartodb.CDB_SetUserQuotaInBytes(0); -- Set user quota to infinite
SELECT cartodb.CDB_CartodbfyTable('test_sync_source');
SELECT cartodb.CDB_CartodbfyTable('test_sync_dest');
UPDATE test_sync_dest SET the_geom = cartodb.CDB_LatLng(lat, lon); -- A "gecoding"
\set QUIET off
SET client_min_messages TO notice;
SELECT cartodb.CDB_SyncTable('test_sync_source', 'public', 'test_sync_dest', '{the_geom, the_geom_webmercator}');
SELECT * FROM test_sync_source ORDER BY cartodb_id;
SELECT * FROM test_sync_dest ORDER BY cartodb_id;

\echo 'It will work with schemas that need quoting'
\set QUIET on
SET client_min_messages TO error;
CREATE SCHEMA "sch-ema";
CREATE TABLE "test_sync_source2" AS SELECT * FROM test_sync_source;
\set QUIET off
SELECT cartodb.CDB_SyncTable('test_sync_source2', 'sch-ema', 'test_sync_dest');
INSERT INTO test_sync_source2(cartodb_id, lat, lon, name) VALUES (6, 6.0, 6.0, 'papaya');
DELETE FROM test_sync_source2 WHERE cartodb_id = 4;
UPDATE test_sync_source2 SET lat = 2.5 WHERE cartodb_id = 2;
SET client_min_messages TO notice;
SELECT cartodb.CDB_SyncTable('test_sync_source2', 'sch-ema', 'test_sync_dest');

\echo 'It will work with table names that need quoting'
\set QUIET on
SET client_min_messages TO error;
CREATE TABLE "test-sync-source" AS SELECT * FROM test_sync_source;
\set QUIET off
SELECT cartodb.CDB_SyncTable('test-sync-source', 'public', 'test-sync-dest');
INSERT INTO "test-sync-source"(cartodb_id, lat, lon, name) VALUES (6, 6.0, 6.0, 'papaya');
DELETE FROM "test-sync-source" WHERE cartodb_id = 4;
UPDATE "test-sync-source" SET lat = 2.5 WHERE cartodb_id = 2;
SET client_min_messages TO notice;
SELECT cartodb.CDB_SyncTable('test-sync-source', 'public', 'test-sync-dest');

\echo 'It will work with column names that need quoting'
\set QUIET on
SET client_min_messages TO error;
ALTER TABLE test_sync_source ADD COLUMN "a-column" int;
\set QUIET off
SELECT cartodb.CDB_SyncTable('test_sync_source', 'public', 'test_sync_dest2');
INSERT INTO test_sync_source(cartodb_id, lat, lon, name) VALUES (6, 6.0, 6.0, 'papaya');
DELETE FROM test_sync_source WHERE cartodb_id = 4;
UPDATE test_sync_source SET lat = 2.5 WHERE cartodb_id = 2;
SET client_min_messages TO notice;
SELECT cartodb.CDB_SyncTable('test_sync_source', 'public', 'test_sync_dest2');

-- Cleanup
ROLLBACK;
