----------------------------------
-- GROUP METADATA API FUNCTIONS
--
-- Meant to be used by CDB_Group_* functions to sync data with the editor.
-- Requires configuration parameter. Example: SELECT @extschema@.CDB_Conf_SetConf('groups_api', '{ "host": "127.0.0.1", "port": 3000, "timeout": 10, "username": "extension", "password": "elephant" }');
----------------------------------

-- TODO: delete this development cleanup before final merge
DROP FUNCTION IF EXISTS @extschema@.CDB_Group_AddMember(group_name text, username text);
DROP FUNCTION IF EXISTS @extschema@.CDB_Group_RemoveMember(group_name text, username text);
DROP FUNCTION IF EXISTS @extschema@._CDB_Group_AddMember_API(group_name text, username text);
DROP FUNCTION IF EXISTS @extschema@._CDB_Group_RemoveMember_API(group_name text, username text);

-- Sends the create group request
CREATE OR REPLACE
FUNCTION @extschema@._CDB_Group_CreateGroup_API(group_name text, group_role text)
    RETURNS VOID AS
$$
    import string

    url = '/api/v1/databases/{0}/groups'
    body = '{ "name": "%s", "database_role": "%s" }' % (group_name, group_role)
    query = "select @extschema@._CDB_Group_API_Request('POST', '%s', '%s', '{200, 409}') as response_status" % (url, body)
    plpy.execute(query)
$$ LANGUAGE 'plpythonu' VOLATILE PARALLEL UNSAFE SECURITY DEFINER;

CREATE OR REPLACE
FUNCTION @extschema@._CDB_Group_DropGroup_API(group_name text)
    RETURNS VOID AS
$$
    import string
    import urllib

    url = '/api/v1/databases/{0}/groups/%s' % (urllib.pathname2url(group_name))

    query = "select @extschema@._CDB_Group_API_Request('DELETE', '%s', '', '{204, 404}') as response_status" % url
    plpy.execute(query)
$$ LANGUAGE 'plpythonu' VOLATILE PARALLEL UNSAFE SECURITY DEFINER;

CREATE OR REPLACE
FUNCTION @extschema@._CDB_Group_RenameGroup_API(old_group_name text, new_group_name text, new_group_role text)
    RETURNS VOID AS
$$
    import string
    import urllib

    url = '/api/v1/databases/{0}/groups/%s' % (urllib.pathname2url(old_group_name))
    body = '{ "name": "%s", "database_role": "%s" }' % (new_group_name, new_group_role)
    query = "select @extschema@._CDB_Group_API_Request('PUT', '%s', '%s', '{200, 409}') as response_status" % (url, body)
    plpy.execute(query)
$$ LANGUAGE 'plpythonu' VOLATILE PARALLEL UNSAFE SECURITY DEFINER;

CREATE OR REPLACE
FUNCTION @extschema@._CDB_Group_AddUsers_API(group_name text, usernames text[])
    RETURNS VOID AS
$$
    import string
    import urllib

    url = '/api/v1/databases/{0}/groups/%s/users' % (urllib.pathname2url(group_name))
    body = "{ \"users\": [\"%s\"] }" % "\",\"".join(usernames)
    query = "select @extschema@._CDB_Group_API_Request('POST', '%s', '%s', '{200, 409}') as response_status" % (url, body)
    plpy.execute(query)
$$ LANGUAGE 'plpythonu' VOLATILE SECURITY DEFINER;

CREATE OR REPLACE
FUNCTION @extschema@._CDB_Group_RemoveUsers_API(group_name text, usernames text[])
    RETURNS VOID AS
$$
    import string
    import urllib

    url = '/api/v1/databases/{0}/groups/%s/users' % (urllib.pathname2url(group_name))
    body = "{ \"users\": [\"%s\"] }" % "\",\"".join(usernames)
    query = "select @extschema@._CDB_Group_API_Request('DELETE', '%s', '%s', '{200, 404}') as response_status" % (url, body)
    plpy.execute(query)
$$ LANGUAGE 'plpythonu' VOLATILE PARALLEL UNSAFE SECURITY DEFINER;

DO LANGUAGE 'plpgsql' $$
BEGIN
    -- Needed for dropping type
    DROP FUNCTION IF EXISTS @extschema@._CDB_Group_API_Conf();
    DROP TYPE IF EXISTS @extschema@._CDB_Group_API_Params;
END
$$;

CREATE OR REPLACE
FUNCTION @extschema@._CDB_Group_Table_GrantPermission_API(group_name text, username text, table_name text, access text)
    RETURNS VOID AS
$$
    import string
    import urllib

    url = '/api/v1/databases/{0}/groups/%s/permission/%s/tables/%s' % (urllib.pathname2url(group_name), username, table_name)
    body = '{ "access": "%s" }' % access
    query = "select @extschema@._CDB_Group_API_Request('PUT', '%s', '%s', '{200, 409}') as response_status" % (url, body)
    plpy.execute(query)
$$ LANGUAGE 'plpythonu' VOLATILE PARALLEL UNSAFE SECURITY DEFINER;

DO LANGUAGE 'plpgsql' $$
BEGIN
    -- Needed for dropping type
    DROP FUNCTION IF EXISTS @extschema@._CDB_Group_API_Conf();
    DROP TYPE IF EXISTS @extschema@._CDB_Group_API_Params;
END
$$;

CREATE OR REPLACE
FUNCTION @extschema@._CDB_Group_Table_RevokeAllPermission_API(group_name text, username text, table_name text)
    RETURNS VOID AS
$$
    import string
    import urllib

    url = '/api/v1/databases/{0}/groups/%s/permission/%s/tables/%s' % (urllib.pathname2url(group_name), username, table_name)
    query = "select @extschema@._CDB_Group_API_Request('DELETE', '%s', '', '{200, 404}') as response_status" % url
    plpy.execute(query)
$$ LANGUAGE 'plpythonu' VOLATILE PARALLEL UNSAFE SECURITY DEFINER;

DO LANGUAGE 'plpgsql' $$
BEGIN
    -- Needed for dropping type
    DROP FUNCTION IF EXISTS @extschema@._CDB_Group_API_Conf();
    DROP TYPE IF EXISTS @extschema@._CDB_Group_API_Params;
END
$$;

CREATE TYPE @extschema@._CDB_Group_API_Params AS (
    host text,
    port int,
    timeout int,
    auth text
);

-- This must be explicitally extracted because "composite types are currently not supported".
-- See http://www.postgresql.org/docs/9.3/static/plpython-database.html.
CREATE OR REPLACE
FUNCTION @extschema@._CDB_Group_API_Conf()
    RETURNS @extschema@._CDB_Group_API_Params AS
$$
    conf = plpy.execute("SELECT @extschema@.CDB_Conf_GetConf('groups_api') conf")[0]['conf']
    if conf is None:
      return None
    else:
      import json
      params = json.loads(conf)
      auth = 'Basic %s' % plpy.execute("SELECT @extschema@._CDB_Group_API_Auth('%s', '%s') as auth" % (params['username'], params['password']))[0]['auth']
      return { "host": params['host'], "port": params['port'], 'timeout': params['timeout'], 'auth': auth }
$$ LANGUAGE 'plpythonu' VOLATILE PARALLEL UNSAFE;

CREATE OR REPLACE
FUNCTION @extschema@._CDB_Group_API_Auth(username text, password text)
    RETURNS TEXT AS
$$
    import base64
    return base64.encodestring('%s:%s' % (username, password)).replace('\n', '')
$$ LANGUAGE 'plpythonu' VOLATILE PARALLEL UNSAFE;

-- url must contain a '%s' placeholder that will be replaced by current_database, for security reasons.
CREATE OR REPLACE
FUNCTION @extschema@._CDB_Group_API_Request(method text, url text, body text, valid_return_codes int[])
    RETURNS int AS
$$
    import httplib

    params = plpy.execute("select c.host, c.port, c.timeout, c.auth from @extschema@._CDB_Group_API_Conf() c;")[0]
    if params['host'] is None:
      return None

    headers = { 'Authorization': params['auth'], 'Content-Type': 'application/json', 'X-Forwarded-Proto': 'https' }

    retry = 3

    last_err = None
    while retry > 0:
      try:
        client = SD['groups_api_client'] = httplib.HTTPConnection(params['host'], params['port'], False, params['timeout'])
        database_name = plpy.execute("select current_database();")[0]['current_database']
        client.request(method, url.format(database_name), body, headers)
        response = client.getresponse()
        assert response.status in valid_return_codes
        return response.status
      except Exception as err:
        retry -= 1
        last_err = err
        plpy.warning('Retrying after: ' + str(err))
        client = SD['groups_api_client'] = None

    if last_err is not None:
      plpy.error('Fatal Group API error: ' + str(last_err))
      raise last_err

    return None
$$ LANGUAGE 'plpythonu' VOLATILE PARALLEL UNSAFE;
revoke all on function @extschema@._CDB_Group_API_Request(text, text, text, int[]) from public;
