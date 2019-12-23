DROP FUNCTION IF EXISTS @extschema@.__CDB_FS_List_Foreign_Schemas_PG(name);
DROP FUNCTION IF EXISTS @extschema@.__CDB_FS_List_Foreign_Tables_PG(name, name);
DROP FUNCTION IF EXISTS @extschema@.__CDB_FS_List_Foreign_Columns_PG(name, name);
DROP FUNCTION IF EXISTS @extschema@.__CDB_FS_List_Foreign_Geometry_Columns_PG(name, name, name);
DROP FUNCTION IF EXISTS @extschema@.CDB_Federated_Server_List_Remote_Schemas(TEXT);
DROP FUNCTION IF EXISTS @extschema@.CDB_Federated_Server_List_Remote_Tables(TEXT, TEXT);
DROP FUNCTION IF EXISTS @extschema@.CDB_Federated_Server_List_Remote_Columns(TEXT, TEXT, TEXT);
