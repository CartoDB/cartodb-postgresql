SELECT session_user; -- postgres
SELECT CDB_Username(); -- (NULL)

-- Add the role fulano with api_key and connect with it
\set QUIET on
CREATE ROLE fulano LOGIN;
GRANT USAGE ON SCHEMA cartodb TO fulano;
GRANT EXECUTE ON FUNCTION CDB_Username() TO fulano;
INSERT INTO cdb_conf (key, value) VALUES ('api_keys_fulano', '{"username": "fulanito", "permissions":[]}');
SET SESSION AUTHORIZATION fulano;
\set QUIET off

SELECT session_user; -- fulano
SELECT CDB_Username(); -- fulanito

-- Remove fulano
\set QUIET on
SET SESSION AUTHORIZATION postgres;
REVOKE USAGE ON SCHEMA cartodb FROM fulano;
REVOKE EXECUTE ON FUNCTION CDB_Username() FROM fulano;
DROP ROLE fulano;
DELETE FROM cdb_conf WHERE key = 'api_keys_fulano';
\set QUIET off