-- Setup
\set QUIET on
SET client_min_messages TO error;
SET SESSION AUTHORIZATION postgres;
\set QUIET off

-- Register a new server
SELECT '1.1', cartodb.CDB_Federated_Server_List_Servers();
-- SELECT '1.2', cartodb.CDB_Federated_Server_Register_PG();
-- SELECT '1.3', cartodb.CDB_Federated_Server_List_Servers();
-- 
-- Register a second server
-- SELECT '2.1', cartodb.CDB_Federated_Server_Register_PG();
-- SELECT '2.2', cartodb.CDB_PG_Federated_Server_List_Servers();
-- 
-- Re-register the second server
-- SELECT '3.1', cartodb.CDB_Federated_Server_Register_PG();
-- SELECT '3.2', cartodb.CDB_PG_Federated_Server_List_Servers();
-- 
-- Unregister #1
-- SELECT '4.1', cartodb.CDB_PG_Federated_Server_Unregister();
-- SELECT '4.2', cartodb.CDB_PG_Federated_Server_List_Servers();
-- 
-- Unregister #2
-- SELECT '5.1', cartodb.CDB_PG_Federated_Server_Unregister();
-- SELECT '5.2', cartodb.CDB_PG_Federated_Server_List_Servers();

-- Should show the appropiate output (database, read-write, user, pass)

-- Test multiple user mappings

-- Should work ok with special characters in the name

-- Should throw with invalid or NULL config

-- -- List works with multiple and single server

-- Cleanup
\set QUIET on

\set QUIET off


