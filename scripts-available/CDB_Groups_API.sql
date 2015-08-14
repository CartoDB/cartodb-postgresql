-- Sends the create group request
CREATE OR REPLACE
FUNCTION cartodb._CDB_Group_CreateGroup_API(database_name text, group_name text, group_role text)
    RETURNS VOID AS
$$
    import httplib
    import base64
    import string
    import json

    try:
      conf = plpy.execute("SELECT cartodb.CDB_Conf_GetConf('groups_api') conf")[0]['conf']
      if conf is None:
        return
      params = json.loads(conf)
      client = httplib.HTTPConnection(params['host'], params['port'], False, params['timeout'])
      url = '/api/v1/databases/%s/groups' % database_name
      body = '{ "name": "%s", "database_role": "%s" }' % (group_name, group_role)
      auth = base64.encodestring('%s:%s' % (params['username'], params['password'])).replace('\n', '')
      headers = { 'Authorization': ('Basic %s' % auth), 'Content-Type': 'application/json' }
      client.request('POST', url, body, headers)
      response = client.getresponse()
      assert response.status == 200
    except Exception as err:
      plpy.warning('group creation error: ' + str(err))
      raise err
    
$$ LANGUAGE 'plpythonu' VOLATILE;

CREATE OR REPLACE
FUNCTION cartodb._CDB_Group_DropGroup_API(database_name text, group_name text)
    RETURNS VOID AS
$$
    import httplib
    import base64
    import string
    import json

    try:
      conf = plpy.execute("SELECT cartodb.CDB_Conf_GetConf('groups_api') conf")[0]['conf']
      if conf is None:
        return
      params = json.loads(conf)
      client = httplib.HTTPConnection(params['host'], params['port'], False, params['timeout'])
      url = '/api/v1/databases/%s/groups/%s' % (database_name, group_name)
      auth = base64.encodestring('%s:%s' % (params['username'], params['password'])).replace('\n', '')
      headers = { 'Authorization': ('Basic %s' % auth), 'Content-Type': 'application/json' }
      client.request('DELETE', url, '', headers)
      response = client.getresponse()
      assert response.status == 200
    except Exception as err:
      plpy.warning('group creation error: ' + str(err))
      raise err
    
$$ LANGUAGE 'plpythonu' VOLATILE;
