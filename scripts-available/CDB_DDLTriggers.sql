--
-- Legacy file
-- Introduced again to make sure that updates do not leave dangling functions
--

DROP FUNCTION IF EXISTS cartodb.cdb_handle_create_table();
DROP FUNCTION IF EXISTS cartodb.cdb_handle_drop_table();
DROP FUNCTION IF EXISTS cartodb.cdb_handle_alter_column();
DROP FUNCTION IF EXISTS cartodb.cdb_handle_drop_column();
DROP FUNCTION IF EXISTS cartodb.cdb_handle_add_column();
DROP FUNCTION IF EXISTS cartodb.cdb_disable_ddl_hooks();
DROP FUNCTION IF EXISTS cartodb.cdb_enable_ddl_hooks();


