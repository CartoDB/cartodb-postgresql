SET client_min_messages TO error;
\set VERBOSITY default

\i test/overviews/fixtures.sql

SELECT _CDB_Aggregable_Attributes_Expression('base_bare_t'::regclass);
SELECT _CDB_Aggregated_Attributes_Expression('base_bare_t'::regclass);
SELECT _CDB_Aggregated_Attributes_Expression('base_bare_t'::regclass, 'tab');

SELECT CDB_CreateOverviews('base_bare_t'::regclass);

SELECT _CDB_Aggregable_Attributes_Expression('base_t'::regclass);
SELECT _CDB_Aggregated_Attributes_Expression('base_t'::regclass);
SELECT _CDB_Aggregated_Attributes_Expression('base_t'::regclass, 'tab');

SELECT CDB_CreateOverviews('base_t'::regclass);

DROP TABLE base_bare_t;
DROP TABLE base_t;
