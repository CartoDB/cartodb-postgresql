SELECT current_user; -- postgres
SELECT CDB_Username(); -- (NULL)

-- Add the role fulano with an api_key and connect with it
\set QUIET on
CREATE ROLE fulano LOGIN;
GRANT USAGE ON SCHEMA cartodb TO fulano;
GRANT EXECUTE ON FUNCTION CDB_Username() TO fulano;
GRANT EXECUTE ON FUNCTION _CDB_Username(text) TO fulano;
INSERT INTO cdb_conf (key, value) VALUES ('api_keys_fulano', '{"username": "fulanito", "permissions":[]}');
SET ROLE fulano;
\set QUIET off

SELECT current_user; -- fulano
SELECT CDB_Username(); -- fulanito

-- Remove fulano
\set QUIET on
SET ROLE postgres;
REVOKE USAGE ON SCHEMA cartodb FROM fulano;
REVOKE EXECUTE ON FUNCTION CDB_Username() FROM fulano;
REVOKE EXECUTE ON FUNCTION _CDB_Username(text) FROM fulano;
DROP ROLE fulano;
\set QUIET off
