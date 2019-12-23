DROP FUNCTION IF EXISTS @extschema@.__CDB_FS_Column_Is_Integer(REGCLASS, NAME);
DROP FUNCTION IF EXISTS @extschema@.__CDB_FS_Column_Is_Geometry(REGCLASS, NAME);
DROP FUNCTION IF EXISTS @extschema@.__CDB_FS_GetColumns(REGCLASS);
DROP FUNCTION IF EXISTS @extschema@.__CDB_FS_Get_View_id_column(TEXT);
DROP FUNCTION IF EXISTS @extschema@.__CDB_FS_Get_View_geom_column(TEXT);
DROP FUNCTION IF EXISTS @extschema@.__CDB_FS_Get_View_webmercator_column(TEXT);
DROP FUNCTION IF EXISTS @extschema@.__CDB_FS_List_Registered_Tables(NAME,TEXT);
DROP FUNCTION IF EXISTS @extschema@.CDB_Federated_Table_Register(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, NAME);
DROP FUNCTION IF EXISTS @extschema@.CDB_Federated_Table_Unregister(TEXT, TEXT, TEXT);
