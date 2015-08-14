-- This will trigger NOTICE if CDB_CONF already exists
DO LANGUAGE 'plpgsql' $$
BEGIN
    CREATE TABLE IF NOT EXISTS cartodb.CDB_CONF ( PARAM TEXT PRIMARY KEY, CONF TEXT NOT NULL );
    EXECUTE format('GRANT SELECT ON cartodb.CDB_CONF TO %s', cartodb.CDB_Organization_Member_Group_Role_Member_Name());
END
$$;

CREATE OR REPLACE
FUNCTION cartodb.CDB_Conf_SetConf(param text, conf text)
    RETURNS void AS $$
BEGIN
    PERFORM cartodb.CDB_Conf_RemoveConf(param);
    EXECUTE 'INSERT INTO cartodb.CDB_CONF (PARAM, CONF) VALUES ($1, $2);' USING param, conf;
END
$$ LANGUAGE PLPGSQL VOLATILE;

CREATE OR REPLACE
FUNCTION cartodb.CDB_Conf_RemoveConf(param text)
    RETURNS void AS $$
BEGIN
    EXECUTE 'DELETE FROM cartodb.CDB_CONF WHERE PARAM = $1;' USING param;
END
$$ LANGUAGE PLPGSQL VOLATILE;

CREATE OR REPLACE
FUNCTION cartodb.CDB_Conf_GetConf(param text)
    RETURNS TEXT AS $$
DECLARE
    conf TEXT;
BEGIN
    EXECUTE 'SELECT CONF FROM cartodb.CDB_CONF WHERE PARAM = $1;' INTO conf USING param;
    RETURN conf;
END
$$ LANGUAGE PLPGSQL STABLE;
