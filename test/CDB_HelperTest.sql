-- Test unique identifier creation with normal length normal relname
SELECT * FROM cartodb._CDB_Unique_Identifier(NULL, 'relname', NULL);

-- Test unique identifier creation with prefix with normal length normal relname
SELECT * FROM cartodb._CDB_Unique_Identifier('prefix_', 'relname', NULL);

-- Test unique identifier creation with suffix with normal length normal relname
SELECT * FROM cartodb._CDB_Unique_Identifier(NULL, 'relname', '_suffix');

-- Test unique identifier creation with long length normal relname
SELECT * FROM cartodb._CDB_Unique_Identifier(NULL, 'largolargolargolargolargolargolargolargolargolargolargolargolar', NULL);

-- Test unique identifier creation with prefix with long length normal relname
SELECT * FROM cartodb._CDB_Unique_Identifier('prefix_', 'largolargolargolargolargolargolargolargolargolargolargolargolar', NULL);

-- Test new identifier is found when name is taken from previous case
CREATE TABLE prefix_largolargolargolargolargolargolargolargolargolargola (name text);
SELECT * FROM cartodb._CDB_Unique_Identifier('prefix_', 'largolargolargolargolargolargolargolargolargolargolargolargolar', NULL);
DROP TABLE prefix_largolargolargolargolargolargolargolargolargolargola;

-- Test unique identifier creation with suffix with long length normal relname
SELECT * FROM cartodb._CDB_Unique_Identifier(NULL, 'largolargolargolargolargolargolargolargolargolargolargolargolar', '_suffix');

-- Test new identifier is found when name is taken from previous case
CREATE TABLE largolargolargolargolargolargolargolargolargolargola_suffix (name text);
SELECT * FROM cartodb._CDB_Unique_Identifier(NULL, 'largolargolargolargolargolargolargolargolargolargolargolargolar', '_suffix');
DROP TABLE largolargolargolargolargolargolargolargolargolargola_suffix;

-- Test unique identifier creation with normal length UTF8 relname
SELECT * FROM cartodb._CDB_Unique_Identifier(NULL, 'piraña', NULL);

-- Test unique identifier creation with prefix with normal length UTF8 relname
SELECT * FROM cartodb._CDB_Unique_Identifier('prefix_', 'piraña', NULL);

-- Test unique identifier creation with suffix with normal length UTF8 relname
SELECT * FROM cartodb._CDB_Unique_Identifier(NULL, 'piraña', '_suffix');

-- Test unique identifier creation with long length UTF8 relname
SELECT * FROM cartodb._CDB_Unique_Identifier(NULL, 'piñaácidpiñaácidpiñaácidpiñaácidpiñaácidpiñaácidpin', NULL);

-- Test unique identifier creation with prefix with long length UTF8 relname
SELECT * FROM cartodb._CDB_Unique_Identifier('prefix_', 'piñaácidpiñaácidpiñaácidpiñaácidpiñaácidpiñaácidpin', NULL);

-- Test new identifier is found when name is taken from previous case
CREATE TABLE prefix_piñaácidpiñaácidpiñaácidpiñaácidpiñaácidpi (name text);
SELECT * FROM cartodb._CDB_Unique_Identifier('prefix_', 'piñaácidpiñaácidpiñaácidpiñaácidpiñaácidpiñaácidpin', NULL);
DROP TABLE prefix_piñaácidpiñaácidpiñaácidpiñaácidpiñaácidpi;

-- Test unique identifier creation with suffix with long length UTF8 relname
SELECT * FROM cartodb._CDB_Unique_Identifier(NULL, 'piñaácidpiñaácidpiñaácidpiñaácidpiñaácidpiñaácidpin', '_suffix');

-- Test new identifier is found when name is taken from previous case
CREATE TABLE piñaácidpiñaácidpiñaácidpiñaácidpiñaácidpi_suffix (name text);
SELECT * FROM cartodb._CDB_Unique_Identifier(NULL, 'piñaácidpiñaácidpiñaácidpiñaácidpiñaácidpiñaácidpin', '_suffix');
DROP TABLE piñaácidpiñaácidpiñaácidpiñaácidpiñaácidpi_suffix;

CREATE TABLE test (name text);
-- Test unique identifier creation with normal length normal colname
SELECT * FROM cartodb._CDB_Unique_Column_Identifier(NULL, 'colname', NULL, 'test'::regclass);

-- Test unique identifier creation with prefix with normal length normal colname
SELECT * FROM cartodb._CDB_Unique_Column_Identifier('prefix_', 'colname', NULL, 'test'::regclass);

-- Test unique identifier creation with suffix with normal length normal colname
SELECT * FROM cartodb._CDB_Unique_Column_Identifier(NULL, 'colname', '_suffix', 'test'::regclass);

-- Test unique identifier creation with long length normal colname
SELECT * FROM cartodb._CDB_Unique_Column_Identifier(NULL, 'largolargolargolargolargolargolargolargolargolargolargolargolar', NULL, 'test'::regclass);

-- Test unique identifier creation with prefix with long length normal colname
SELECT * FROM cartodb._CDB_Unique_Column_Identifier('prefix_', 'largolargolargolargolargolargolargolargolargolargolargolargolar', NULL, 'test'::regclass);
DROP TABLE test;

-- Test new identifier is found when name is taken from previous case
CREATE TABLE test (prefix_largolargolargolargolargolargolargolargolargolargola text);
SELECT * FROM cartodb._CDB_Unique_Column_Identifier('prefix_', 'largolargolargolargolargolargolargolargolargolargolargolargolar', NULL, 'test'::regclass);
DROP TABLE test;

-- Test unique identifier creation with suffix with long length normal colname
CREATE TABLE test (name text);
SELECT * FROM cartodb._CDB_Unique_Column_Identifier(NULL, 'largolargolargolargolargolargolargolargolargolargolargolargolar', '_suffix', 'test'::regclass);
DROP TABLE test;

-- Test new identifier is found when name is taken from previous case
CREATE TABLE test (largolargolargolargolargolargolargolargolargolargola_suffix text);
SELECT * FROM cartodb._CDB_Unique_Column_Identifier(NULL, 'largolargolargolargolargolargolargolargolargolargolargolargolar', '_suffix', 'test'::regclass);
DROP TABLE test;

CREATE TABLE test (name text);
-- Test unique identifier creation with normal length UTF8 colname
SELECT * FROM cartodb._CDB_Unique_Column_Identifier(NULL, 'piraña', NULL, 'test'::regclass);

-- Test unique identifier creation with prefix with normal length UTF8 colname
SELECT * FROM cartodb._CDB_Unique_Column_Identifier('prefix_', 'piraña', NULL, 'test'::regclass);

-- Test unique identifier creation with suffix with normal length UTF8 colname
SELECT * FROM cartodb._CDB_Unique_Column_Identifier(NULL, 'piraña', '_suffix', 'test'::regclass);

-- Test unique identifier creation with long length UTF8 colname
SELECT * FROM cartodb._CDB_Unique_Column_Identifier(NULL, 'piñaácidpiñaácidpiñaácidpiñaácidpiñaácidpiñaácidpin', NULL, 'test'::regclass);

-- Test unique identifier creation with prefix with long length UTF8 colname
SELECT * FROM cartodb._CDB_Unique_Column_Identifier('prefix_', 'piñaácidpiñaácidpiñaácidpiñaácidpiñaácidpiñaácidpin', NULL, 'test'::regclass);
DROP TABLE test;

-- Test new identifier is found when name is taken from previous case
CREATE TABLE test (prefix_piñaácidpiñaácidpiñaácidpiñaácidpiñaácidpi text);
SELECT * FROM cartodb._CDB_Unique_Column_Identifier('prefix_', 'piñaácidpiñaácidpiñaácidpiñaácidpiñaácidpiñaácidpin', NULL, 'test'::regclass);
DROP TABLE test;

-- Test unique identifier creation with suffix with long length UTF8 colname
CREATE TABLE test (name text);
SELECT * FROM cartodb._CDB_Unique_Column_Identifier(NULL, 'piñaácidpiñaácidpiñaácidpiñaácidpiñaácidpiñaácidpin', '_suffix', 'test'::regclass);
DROP TABLE test;

-- Test new identifier is found when name is taken from previous case
CREATE TABLE test (piñaácidpiñaácidpiñaácidpiñaácidpiñaácidpi_suffix text);
SELECT * FROM cartodb._CDB_Unique_Column_Identifier(NULL, 'piñaácidpiñaácidpiñaácidpiñaácidpiñaácidpiñaácidpin', '_suffix', 'test'::regclass);
DROP TABLE test;

-- Test _CDB_Octet_Truncate simple case
SELECT * FROM cartodb._CDB_Octet_Truncate('piraña', 5);

-- Test _CDB_Octet_Truncate UTF8 case
SELECT * FROM cartodb._CDB_Octet_Truncate('piraña', 6);

-- Test _CDB_Octet_Truncate UTF8 case
SELECT * FROM cartodb._CDB_Octet_Truncate('piraña', 7);

-- Test _CDB_Table_Exists
CREATE TABLE public.this_table_exists();
SELECT cartodb._CDB_Table_Exists('this_table_does_not_exist');
SELECT cartodb._CDB_Table_Exists('this_schema_does_not_exist.this_table_does_not_exist');
SELECT cartodb._CDB_Table_Exists('this_table_exists');
SELECT cartodb._CDB_Table_Exists('public.this_table_exists');
SELECT cartodb._CDB_Table_Exists('raster_overviews'); -- view created by postgis
SELECT cartodb._CDB_Table_Exists('public.raster_overviews');
DROP TABLE public.this_table_exists
