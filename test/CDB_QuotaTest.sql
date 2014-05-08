set client_min_messages to ERROR;
\set VERBOSITY terse
CREATE TABLE big(a int);
SELECT CDB_CartodbfyTable('big');
INSERT INTO big SELECT generate_series(1,1024);
SELECT CDB_SetUserQuotaInBytes(8);
INSERT INTO big VALUES (1);
SELECT CDB_SetUserQuotaInBytes(0);
INSERT INTO big VALUES (1);
DROP TABLE big;
set client_min_messages to NOTICE;
