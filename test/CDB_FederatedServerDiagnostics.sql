\echo '%% It raises an error if the server does not exist'
SELECT '1.1', cartodb.CDB_Federated_Server_Diagnostics(server => 'doesNotExist');
