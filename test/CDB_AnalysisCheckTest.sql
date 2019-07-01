SET client_min_messages TO error;
\set VERBOSITY terse

SELECT CDB_SetUserQuotaInBytes(1000000);
SELECT _CDB_AnalysisTablesInSchema('public');
SELECT _CDB_AnalysisDataSize('public');
CREATE TABLE analysis_2f13a3dbd7_41bd92976fc6dd97072afe4ee450054f4c0715d5(id int);
CREATE TABLE analysis_2f13a3dbd7_f00cee44e9e6152b450bde3a92eb9ae0d099da94(id int);
CREATE TABLE analysis_2f13a3dbd7_f00cee44e9e6152b450bde3a92eb9ae0d099da9(id int);
SELECT _CDB_AnalysisTablesInSchema('public') t ORDER BY t;
SELECT _CDB_AnalysisDataSize('public');
SELECT CDB_CheckAnalysisQuota('analysis_2f13a3dbd7_f00cee44e9e6152b450bde3a92eb9ae0d099da94');
SELECT CDB_SetUserQuotaInBytes(1);
SELECT CDB_CheckAnalysisQuota('analysis_2f13a3dbd7_f00cee44e9e6152b450bde3a92eb9ae0d099da94');
INSERT INTO analysis_2f13a3dbd7_41bd92976fc6dd97072afe4ee450054f4c0715d5(id) VALUES (1),(2),(3),(4),(5);
SELECT CDB_CheckAnalysisQuota('analysis_2f13a3dbd7_f00cee44e9e6152b450bde3a92eb9ae0d099da94');
DROP TABLE analysis_2f13a3dbd7_41bd92976fc6dd97072afe4ee450054f4c0715d5;
DROP TABLE analysis_2f13a3dbd7_f00cee44e9e6152b450bde3a92eb9ae0d099da94;
DROP TABLE analysis_2f13a3dbd7_f00cee44e9e6152b450bde3a92eb9ae0d099da9;
DROP FUNCTION "public"._CDB_UserQuotaInBytes();
