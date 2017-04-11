SET client_min_messages TO error;
\set VERBOSITY terse
CREATE TABLE tmptab1(id INT);
INSERT INTO tmptab1(id) VALUES (1), (2), (3);
CREATE TABLE tmptab2(id INT, value NUMERIC);
INSERT INTO tmptab2(id, value) VALUES (1, 10.0), (2, 20.0);
SELECT CDB_EstimateRowCount('SELECT SUM(value) FROM tmptab1 INNER JOIN tmptab2 ON (tmptab1.id = tmptab2.id);') AS row_count;
SELECT CDB_EstimateRowCount('UPDATE tmptab2 SET value = 30 WHERE id=2;') AS row_count;
DROP TABLE tmptab2;
DROP TABLE tmptab1;
