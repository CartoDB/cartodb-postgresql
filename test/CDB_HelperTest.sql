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
CREATE TABLE prefix_largolargolargolargolargolargolargolargolargolargolar (name text);
SELECT * FROM cartodb._CDB_Unique_Identifier('prefix_', 'largolargolargolargolargolargolargolargolargolargolargolargolar', NULL);
DROP TABLE prefix_largolargolargolargolargolargolargolargolargolargolar;

-- Test unique identifier creation with suffix with long length normal relname
SELECT * FROM cartodb._CDB_Unique_Identifier(NULL, 'largolargolargolargolargolargolargolargolargolargolargolargolar', '_suffix');

-- Test new identifier is found when name is taken from previous case
CREATE TABLE largolargolargolargolargolargolargolargolargolargolar_suffix (name text);
SELECT * FROM cartodb._CDB_Unique_Identifier(NULL, 'largolargolargolargolargolargolargolargolargolargolargolargolar', '_suffix');
DROP TABLE largolargolargolargolargolargolargolargolargolargolar_suffix;

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

-- Test unique identifier creation with normal length normal colname
SELECT * FROM cartodb._CDB_Unique_Column_Identifier(NULL, 'colname', NULL);

-- Test unique identifier creation with prefix with normal length normal colname
SELECT * FROM cartodb._CDB_Unique_Column_Identifier('prefix_', 'colname', NULL);

-- Test unique identifier creation with suffix with normal length normal colname
SELECT * FROM cartodb._CDB_Unique_Column_Identifier(NULL, 'colname', '_suffix');

-- Test unique identifier creation with long length normal colname
SELECT * FROM cartodb._CDB_Unique_Column_Identifier(NULL, 'largolargolargolargolargolargolargolargolargolargolargolargolar', NULL);

-- Test unique identifier creation with prefix with long length normal colname
SELECT * FROM cartodb._CDB_Unique_Column_Identifier('prefix_', 'largolargolargolargolargolargolargolargolargolargolargolargolar', NULL);

-- Test new identifier is found when name is taken from previous case
CREATE TABLE test (prefix_largolargolargolargolargolargolargolargolargolargolar text);
SELECT * FROM cartodb._CDB_Unique_Column_Identifier('prefix_', 'largolargolargolargolargolargolargolargolargolargolargolargolar', NULL);
DROP TABLE test;

-- Test unique identifier creation with suffix with long length normal colname
SELECT * FROM cartodb._CDB_Unique_Column_Identifier(NULL, 'largolargolargolargolargolargolargolargolargolargolargolargolar', '_suffix');

-- Test new identifier is found when name is taken from previous case
CREATE TABLE test (largolargolargolargolargolargolargolargolargolargolar_suffix text);
SELECT * FROM cartodb._CDB_Unique_Column_Identifier(NULL, 'largolargolargolargolargolargolargolargolargolargolargolargolar', '_suffix');
DROP TABLE test;

-- Test unique identifier creation with normal length UTF8 colname
SELECT * FROM cartodb._CDB_Unique_Column_Identifier(NULL, 'piraña', NULL);

-- Test unique identifier creation with prefix with normal length UTF8 colname
SELECT * FROM cartodb._CDB_Unique_Column_Identifier('prefix_', 'piraña', NULL);

-- Test unique identifier creation with suffix with normal length UTF8 colname
SELECT * FROM cartodb._CDB_Unique_Column_Identifier(NULL, 'piraña', '_suffix');

-- Test unique identifier creation with long length UTF8 colname
SELECT * FROM cartodb._CDB_Unique_Column_Identifier(NULL, 'piñaácidpiñaácidpiñaácidpiñaácidpiñaácidpiñaácidpin', NULL);

-- Test unique identifier creation with prefix with long length UTF8 colname
SELECT * FROM cartodb._CDB_Unique_Column_Identifier('prefix_', 'piñaácidpiñaácidpiñaácidpiñaácidpiñaácidpiñaácidpin', NULL);

-- Test new identifier is found when name is taken from previous case
CREATE TABLE test (prefix_piñaácidpiñaácidpiñaácidpiñaácidpiñaácidpi text);
SELECT * FROM cartodb._CDB_Unique_Column_Identifier('prefix_', 'piñaácidpiñaácidpiñaácidpiñaácidpiñaácidpiñaácidpin', NULL);
DROP TABLE test;

-- Test unique identifier creation with suffix with long length UTF8 colname
SELECT * FROM cartodb._CDB_Unique_Column_Identifier(NULL, 'piñaácidpiñaácidpiñaácidpiñaácidpiñaácidpiñaácidpin', '_suffix');

-- Test new identifier is found when name is taken from previous case
CREATE TABLE test (piñaácidpiñaácidpiñaácidpiñaácidpiñaácidpi_suffix text);
SELECT * FROM cartodb._CDB_Unique_Column_Identifier(NULL, 'piñaácidpiñaácidpiñaácidpiñaácidpiñaácidpiñaácidpin', '_suffix');
DROP TABLE test;

-- Test _CDB_Trim_Octets simple case
SELECT * FROM cartodb._CDB_Octet_Trim('piraña', 1);

-- Test _CDB_Octet_Trim UTF8 case
SELECT * FROM cartodb._CDB_Octet_Trim('piraña', 2);

-- Test _CDB_Octet_Trim UTF8 case
SELECT * FROM cartodb._CDB_Octet_Trim('piraña', 3);