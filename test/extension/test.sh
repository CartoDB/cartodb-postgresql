#!/bin/sh

#
# Tests for the extension since version 0.5.0. They don't replace SQL based ones, for now need to run both
#

# It is expected that you run this script as a PostgreSQL superuser, for example:
#
#   PGUSER=postgres bash ./test.sh
#

DATABASE=test_extension
CMD='echo psql'
CMD=psql

OK=0
PARTIALOK=0

function set_failed() {
    OK=1
    PARTIALOK=1
}


function clear_partial_result() {
    PARTIALOK=0
}


function sql() {
    local ROLE
    local QUERY
    if [[ $# -ge 2 ]]
    then
        ROLE="$1"
        QUERY="$2"
    else
        QUERY="$1"
    fi

    if [ -n "${ROLE}" ]; then
      log_debug "Executing query '${QUERY}' as ${ROLE}"
      RESULT=`${CMD} -U "${ROLE}" ${DATABASE} -c "${QUERY}" -A -t`
    else
      log_debug "Executing query '${QUERY}'"
      RESULT=`${CMD} ${DATABASE} -c "${QUERY}" -A -t`
    fi
    CODERESULT=$?

    echo ${RESULT}
    echo

    if [[ ${CODERESULT} -ne 0 ]]
    then
        echo -n "FAILED TO EXECUTE QUERY: "
        log_warning "${QUERY}"
        if [[ "$3" != "fails" ]]
        then
            log_error "${QUERY}"
            set_failed
        fi
    else
        if [[ "$3" == "fails" ]]
        then
            log_error "QUERY: '${QUERY}' was expected to fail and it did not fail"
            set_failed
        fi
    fi

    if [[ "$3" == "should" ]]
    then
        if [[ "${RESULT}" != "$4" ]]
        then
            log_error "QUERY '${QUERY}' expected result '${4}' but got '${RESULT}'"
            set_failed
        fi
    fi

    if [[ "$3" == "should-not" ]]
    then
        if [[ "${RESULT}" == "$4" ]]
        then
            log_error "QUERY '${QUERY}' did not expect '${RESULT}'"
            set_failed
        fi
    fi
}


function log_info()
{
    echo
    echo
    echo
    _log "1;34m" "$1"
}

function log_error() {
    _log "1;31m" "$1"
}

function log_debug() {
    _log "1;32m" "> $1"
}

function log_warning() {
    _log "0;33m" "$1"
}

function _log() {
    echo -e "\033[$1$2\033[0m"
}

# '############################ HELPERS #############################'
function create_role_and_schema() {
    local ROLE=$1
    sql "CREATE ROLE ${ROLE} LOGIN;"
    sql "GRANT CONNECT ON DATABASE \"${DATABASE}\" TO ${ROLE};"
    sql "CREATE SCHEMA ${ROLE} AUTHORIZATION ${ROLE};"
    sql "SELECT cartodb.CDB_Organization_Create_Member('${ROLE}');"
}


function drop_role_and_schema() {
    local ROLE=$1
    sql "DROP SCHEMA \"${ROLE}\" CASCADE;"
    sql "REVOKE CONNECT ON DATABASE \"${DATABASE}\" FROM \"${ROLE}\";"
    sql "DROP ROLE \"${ROLE}\";"
}


function create_table() {
    if [[ $# -ne 2 ]]
    then
        log_error "create_table requires two arguments: role and table_name"
        exit 1
    fi
    local ROLE="$1"
    local TABLENAME="$2"
    sql ${ROLE} "CREATE TABLE ${ROLE}.${TABLENAME} ( a int );"
}


function create_raster_table() {
    if [[ $# -ne 2 ]]
    then
        log_error "create_raster_table requires two arguments: role and table_name"
        exit 1
    fi
    local RASTER_COL="the_raster_webmercator"
    local ROLE="$1"
    local TABLENAME="$2"
    local OVERVIEW_TABLENAME="o_2_${TABLENAME}"
    sql ${ROLE} "CREATE TABLE ${ROLE}.${TABLENAME} (rid serial PRIMARY KEY, ${RASTER_COL} raster);"

    sql ${ROLE} "CREATE TABLE ${ROLE}.${OVERVIEW_TABLENAME} (rid serial PRIMARY KEY, ${RASTER_COL} raster);"

    sql ${ROLE} "SELECT AddOverviewConstraints('${ROLE}','${OVERVIEW_TABLENAME}','${RASTER_COL}','${ROLE}','${TABLENAME}','${RASTER_COL}',2);"
}

function drop_raster_table() {
    if [[ $# -ne 2 ]]
    then
        log_error "drop_raster_table requires two arguments: role and table_name"
        exit 1
    fi
    local ROLE="$1"
    local TABLENAME="$2"
    local OVERVIEW_TABLENAME="o_2_${TABLENAME}"

    sql ${ROLE} "DROP TABLE ${ROLE}.${OVERVIEW_TABLENAME};"
    sql ${ROLE} "DROP TABLE ${ROLE}.${TABLENAME};"
}

function setup_database() {
    ${CMD} -c "CREATE DATABASE ${DATABASE}"
    sql "CREATE SCHEMA cartodb;"
    sql "GRANT USAGE ON SCHEMA cartodb TO public;"
    sql "CREATE EXTENSION postgis;"
    sql "CREATE EXTENSION plpythonu;"

    log_info "########################### BOOTSTRAP ###########################"
    ${CMD} -d ${DATABASE} -f scripts-available/CDB_Organizations.sql
    ${CMD} -d ${DATABASE} -f scripts-available/CDB_OverviewsSupport.sql
    ${CMD} -d ${DATABASE} -f scripts-available/CDB_AnalysisSupport.sql
    # trick to allow forcing a schema when loading SQL files (see: http://bit.ly/1HeLnhL)
    ${CMD} -d ${DATABASE} -f test/extension/run_at_cartodb_schema.sql
}

function setup() {
    setup_database

    log_info "############################# SETUP #############################"
    create_role_and_schema cdb_testmember_1
    create_role_and_schema cdb_testmember_2

    create_table cdb_testmember_1 foo
    sql cdb_testmember_1 'INSERT INTO cdb_testmember_1.foo VALUES (1), (2), (3), (4), (5), (6);'
    sql cdb_testmember_1 'SELECT * FROM cdb_testmember_1.foo;'

    create_table cdb_testmember_2 bar
    sql cdb_testmember_2 'INSERT INTO bar VALUES (1), (2), (3);'
    sql cdb_testmember_2 'SELECT * FROM cdb_testmember_2.bar;'
}


function tear_down_database() {
    ${CMD} -c "DROP DATABASE ${DATABASE}"
}
function tear_down() {
    log_info "########################### USER TEAR DOWN ###########################"
    sql cdb_testmember_1 "SELECT * FROM cartodb.CDB_Organization_Remove_Access_Permission('cdb_testmember_1', 'foo', 'cdb_testmember_2');"
    sql cdb_testmember_2 "SELECT * FROM cartodb.CDB_Organization_Remove_Access_Permission('cdb_testmember_2', 'bar', 'cdb_testmember_1');"

    sql cdb_testmember_1 'DROP TABLE cdb_testmember_1.foo;'
    sql cdb_testmember_2 'DROP TABLE cdb_testmember_2.bar;'

    sql "DROP SCHEMA cartodb CASCADE"

    log_info "########################### TEAR DOWN ###########################"
    sql 'DROP SCHEMA cdb_testmember_1 CASCADE;'
    sql 'DROP SCHEMA cdb_testmember_2 CASCADE;'

    sql "REVOKE CONNECT ON DATABASE \"${DATABASE}\" FROM cdb_testmember_1;"
    sql "REVOKE CONNECT ON DATABASE \"${DATABASE}\" FROM cdb_testmember_2;"

    sql 'DROP ROLE cdb_testmember_1;'
    sql 'DROP ROLE cdb_testmember_2;'

    tear_down_database
    DATABASE=postgres sql postgres 'DROP ROLE IF EXISTS publicuser';
}


function run_tests() {
    local FAILED_TESTS=()

    local TESTS
    if [[ $# -ge 1 ]]
    then
        if [[ $# -eq 1 ]]
        then
            TESTS=`cat $0 | grep -o "$1[^\(]*"`
        else
            TESTS="$@"
        fi
    else
        TESTS=`cat $0 | perl -n -e'/function (test.*)\(\)/ && print "$1\n"'`
    fi
    for t in ${TESTS}
    do
        echo "####################################################################"
        echo "#"
        echo "# Running: ${t}"
        echo "#"
        echo "####################################################################"
        clear_partial_result
        setup
        eval ${t}
        if [[ ${PARTIALOK} -ne 0 ]]
        then
            FAILED_TESTS+=(${t})
        fi
        tear_down
    done
    if [[ ${OK} -ne 0 ]]
    then
        echo
        log_error "The following tests are failing:"
        printf -- '\t%s\n' "${FAILED_TESTS[@]}"
    fi
}


#################################################### TESTS GO HERE ####################################################


# Tests quota checking taking into account both geom and raster tables
function test_quota_for_each_user() {
    # Normal tables add 4096 bytes
    # Raster tables no longer add anything so also count as 4096

    sql cdb_testmember_1 "SELECT cartodb.CDB_UserDataSize('cdb_testmember_1'::TEXT);" should 4096
    sql cdb_testmember_2 "SELECT cartodb.CDB_UserDataSize('cdb_testmember_2'::TEXT);" should 4096

    create_raster_table cdb_testmember_1 raster_1
    create_raster_table cdb_testmember_2 raster_2

    sql cdb_testmember_1 "SELECT cartodb.CDB_UserDataSize('cdb_testmember_1'::TEXT);" should 20480
    sql cdb_testmember_2 "SELECT cartodb.CDB_UserDataSize('cdb_testmember_2'::TEXT);" should 20480

    create_raster_table cdb_testmember_1 raster_3

    sql cdb_testmember_1 "SELECT cartodb.CDB_UserDataSize('cdb_testmember_1'::TEXT);" should 36864
    sql cdb_testmember_2 "SELECT cartodb.CDB_UserDataSize('cdb_testmember_2'::TEXT);" should 20480

    drop_raster_table cdb_testmember_1 raster_1
    drop_raster_table cdb_testmember_2 raster_2
    drop_raster_table cdb_testmember_1 raster_3

    sql cdb_testmember_1 "SELECT cartodb.CDB_UserDataSize('cdb_testmember_1'::TEXT);" should 4096
    sql cdb_testmember_2 "SELECT cartodb.CDB_UserDataSize('cdb_testmember_2'::TEXT);" should 4096
}

function test_cdb_tablemetadatatouch() {
    sql "CREATE TABLE touch_example (a int)"
    sql postgres "SELECT updated_at FROM CDB_TableMetadata WHERE tabname = 'touch_example'::regclass;" should ''
    sql "SELECT CDB_TableMetadataTouch('touch_example');"
    sql postgres "SELECT updated_at FROM CDB_TableMetadata WHERE tabname = 'touch_example'::regclass;" should-not ''

    # Another call doesn't fail
    sql "SELECT CDB_TableMetadataTouch('touch_example');"
    sql postgres "SELECT updated_at FROM CDB_TableMetadata WHERE tabname = 'touch_example'::regclass;" should-not ''

    # Works with qualified tables
    sql "SELECT CDB_TableMetadataTouch('public.touch_example');"
    sql "SELECT CDB_TableMetadataTouch('public.\"touch_example\"');"
    sql "SELECT CDB_TableMetadataTouch('\"public\".touch_example');"
    sql "SELECT CDB_TableMetadataTouch('\"public\".\"touch_example\"');"

    # Works with OID
    sql postgres "SELECT tabname from CDB_TableMetadata;" should 'touch_example'
    sql postgres "SELECT count(*) from CDB_TableMetadata;" should 1
    TABLE_OID=`${CMD} -U postgres ${DATABASE} -c "SELECT attrelid FROM pg_attribute WHERE attrelid = 'touch_example'::regclass limit 1;" -A -t`

    # quoted OID works
    sql "SELECT CDB_TableMetadataTouch('${TABLE_OID}');"
    sql postgres "SELECT tabname from CDB_TableMetadata;" should 'touch_example'
    sql postgres "SELECT count(*) from CDB_TableMetadata;" should 1

    # non quoted OID works
    sql "SELECT CDB_TableMetadataTouch(${TABLE_OID});"
    sql postgres "SELECT tabname from CDB_TableMetadata;" should 'touch_example'
    sql postgres "SELECT count(*) from CDB_TableMetadata;" should 1

    #### test tear down
    sql 'DROP TABLE touch_example;'
}

function test_cdb_tablemetadatatouch_fails_for_unexistent_table() {
    sql postgres "SELECT CDB_TableMetadataTouch('unexistent_example');" fails
}

function test_cdb_tablemetadatatouch_fails_from_user_without_permission() {
    sql "CREATE TABLE touch_example (a int);"
    sql postgres "SELECT CDB_TableMetadataTouch('touch_example');"

    sql cdb_testmember_1 "SELECT CDB_TableMetadataTouch('touch_example');" fails

    sql postgres "GRANT ALL ON CDB_TableMetadata TO cdb_testmember_1;"
    sql cdb_testmember_1 "SELECT CDB_TableMetadataTouch('touch_example');"

    sql postgres "REVOKE ALL ON CDB_TableMetadata FROM cdb_testmember_1;"
}

function test_cdb_tablemetadatatouch_fully_qualifies_names() {
    sql postgres "CREATE TABLE touch_invalidations (table_name text);"
    sql postgres "create or replace function cartodb.cdb_invalidate_varnish(table_name text) returns void as \$\$ begin insert into touch_invalidations select table_name; end; \$\$ language 'plpgsql';"

    #default schema
    sql "CREATE TABLE touch_example (a int);"
    sql postgres "SELECT CDB_TableMetadataTouch('touch_example');"
    sql postgres "SELECT table_name FROM touch_invalidations" should "public.touch_example"
    sql postgres "TRUNCATE TABLE touch_invalidations"
    sql postgres "DROP TABLE touch_example"

    #setup different schema
    sql postgres "CREATE SCHEMA test_schema;"
    sql postgres "CREATE TABLE test_schema.touch_example (a int);"

    #different schema outside search_path
    sql postgres "SELECT CDB_TableMetadataTouch('test_schema.touch_example');"
    sql postgres "SELECT table_name FROM touch_invalidations" should "test_schema.touch_example"
    sql postgres "TRUNCATE TABLE touch_invalidations"

    #different schema in default search_path
    sql postgres "SET search_path=test_schema,public,cartodb; SELECT CDB_TableMetadataTouch('test_schema.touch_example');"
    sql postgres "SELECT table_name FROM touch_invalidations" should "test_schema.touch_example"
    sql postgres "TRUNCATE TABLE touch_invalidations"

    #teardown different schema
    sql postgres 'DROP TABLE test_schema.touch_example;'
    sql postgres 'DROP SCHEMA test_schema;'



    sql postgres 'DROP FUNCTION cartodb.cdb_invalidate_varnish(table_name text);'
    sql postgres 'DROP TABLE touch_invalidations'
}

function test_cdb_column_names() {
    sql cdb_testmember_1 'CREATE TABLE cdb_testmember_1.table_cnames(c int, a int, r int, t int, o int);'
    sql cdb_testmember_2 'CREATE TABLE cdb_testmember_2.table_cnames(d int, b int);'

    sql cdb_testmember_1 "SELECT string_agg(c,'') from (SELECT cartodb.CDB_ColumnNames('table_cnames') c) as s" should "carto"
    sql cdb_testmember_2 "SELECT string_agg(c,'') from (SELECT cartodb.CDB_ColumnNames('table_cnames') c) as s" should "db"

    sql postgres "SELECT string_agg(c,'') from (SELECT cartodb.CDB_ColumnNames('cdb_testmember_1.table_cnames'::regclass) c) as s" should "carto"
    sql postgres "SELECT string_agg(c,'') from (SELECT cartodb.CDB_ColumnNames('cdb_testmember_2.table_cnames') c) as s" should "db"

    # Using schema from owner
    sql cdb_testmember_1 "SELECT string_agg(c,'') from (SELECT cartodb.CDB_ColumnNames('cdb_testmember_1.table_cnames') c) as s" should "carto"

    ## it's not possible to get column names from a table where you don't have permissions
    sql cdb_testmember_2 "SELECT string_agg(c,'') from (SELECT cartodb.CDB_ColumnNames('cdb_testmember_1.table_cnames') c) as s" fails

    sql cdb_testmember_1 'DROP TABLE cdb_testmember_1.table_cnames'
    sql cdb_testmember_2 'DROP TABLE cdb_testmember_2.table_cnames'
}

function test_cdb_column_type() {
    sql cdb_testmember_1 'CREATE TABLE cdb_testmember_1.table_ctype(c int, a int, r int, t int, o int);'
    sql cdb_testmember_2 'CREATE TABLE cdb_testmember_2.table_ctype(c text, a text, r text, t text, o text);'

    sql cdb_testmember_1 "SELECT cartodb.CDB_ColumnType('table_ctype', 'c')" should "integer"
    sql cdb_testmember_2 "SELECT cartodb.CDB_ColumnType('table_ctype', 'c')" should "text"

    sql postgres "SELECT cartodb.CDB_ColumnType('cdb_testmember_1.table_ctype', 'c')" should "integer"
    sql postgres "SELECT cartodb.CDB_ColumnType('cdb_testmember_2.table_ctype', 'c')" should "text"

    sql cdb_testmember_1 'DROP TABLE cdb_testmember_1.table_ctype'
    sql cdb_testmember_2 'DROP TABLE cdb_testmember_2.table_ctype'
}

function test_cdb_querytables_schema_and_table_names_with_dots() {
    ${CMD} -d ${DATABASE} -f scripts-available/CDB_QueryStatements.sql
    ${CMD} -d ${DATABASE} -f scripts-available/CDB_QueryTables.sql

    sql postgres 'CREATE SCHEMA "foo.bar";'
    sql postgres 'CREATE TABLE "foo.bar"."c.a.r.t.o.d.b" (a int);'
    sql postgres 'INSERT INTO "foo.bar"."c.a.r.t.o.d.b" values (1);'
    sql postgres 'SELECT a FROM "foo.bar"."c.a.r.t.o.d.b";' should 1

    sql postgres 'SELECT CDB_QueryTablesText($q$select * from "foo.bar"."c.a.r.t.o.d.b"$q$);' should '{"\"foo.bar\".\"c.a.r.t.o.d.b\""}'
    sql postgres 'SELECT CDB_QueryTables($q$select * from "foo.bar"."c.a.r.t.o.d.b"$q$);' should '{"\"foo.bar\".\"c.a.r.t.o.d.b\""}'

    sql postgres 'DROP TABLE "foo.bar"."c.a.r.t.o.d.b";'
    sql postgres 'DROP SCHEMA "foo.bar";'
}

function test_cdb_querytables_table_name_with_dots() {
    ${CMD} -d ${DATABASE} -f scripts-available/CDB_QueryStatements.sql
    ${CMD} -d ${DATABASE} -f scripts-available/CDB_QueryTables.sql

    sql postgres 'CREATE TABLE "w.a.d.u.s" (a int);';

    sql postgres 'SELECT CDB_QueryTablesText($q$select * from "w.a.d.u.s"$q$);' should '{"public.\"w.a.d.u.s\""}'
    sql postgres 'SELECT CDB_QueryTables($q$select * from "w.a.d.u.s"$q$);' should '{"public.\"w.a.d.u.s\""}'

    sql postgres 'DROP TABLE "w.a.d.u.s";';
}

function test_cdb_querytables_happy_cases() {
    ${CMD} -d ${DATABASE} -f scripts-available/CDB_QueryStatements.sql
    ${CMD} -d ${DATABASE} -f scripts-available/CDB_QueryTables.sql

    sql postgres 'CREATE TABLE wadus (a int);';
    sql postgres 'CREATE TABLE "FOOBAR" (a int);';
    sql postgres 'CREATE SCHEMA foo;'
    sql postgres 'CREATE TABLE foo.wadus (a int);';

    ## See how it does NOT quote anything here
    sql postgres 'SELECT CDB_QueryTablesText($q$select * from wadus$q$);' should '{public.wadus}'
    sql postgres 'SELECT CDB_QueryTablesText($q$select * from foo.wadus$q$);' should '{foo.wadus}'
    sql postgres 'SELECT CDB_QueryTables($q$select * from wadus$q$);' should '{public.wadus}'
    sql postgres 'SELECT CDB_QueryTables($q$select * from foo.wadus$q$);' should '{foo.wadus}'

    ## But it quotes when it's needed even if table name has no dots but was created with quotes
    sql postgres 'SELECT CDB_QueryTablesText($q$select * from "FOOBAR"$q$);' should '{"public.\"FOOBAR\""}'

    sql postgres 'DROP TABLE wadus;'
    sql postgres 'DROP TABLE "FOOBAR";'
    sql postgres 'DROP TABLE foo.wadus;'
    sql postgres 'DROP SCHEMA foo;'
}

function test_foreign_tables() {
    ${CMD} -d ${DATABASE} -f scripts-available/CDB_QueryStatements.sql
    ${CMD} -d ${DATABASE} -f scripts-available/CDB_QueryTables.sql
    ${CMD} -d ${DATABASE} -f scripts-available/CDB_TableMetadata.sql
    ${CMD} -d ${DATABASE} -f scripts-available/CDB_Conf.sql
    ${CMD} -d ${DATABASE} -f scripts-available/CDB_ForeignTable.sql


    DATABASE=fdw_target setup_database
    ${CMD} -d fdw_target -f scripts-available/CDB_QueryStatements.sql
    ${CMD} -d fdw_target -f scripts-available/CDB_QueryTables.sql
    ${CMD} -d fdw_target -f scripts-available/CDB_TableMetadata.sql

    DATABASE=fdw_target sql postgres "DO
\$\$
BEGIN
   IF NOT EXISTS (
      SELECT *
      FROM   pg_catalog.pg_user
      WHERE  usename = 'publicuser') THEN

      CREATE ROLE publicuser LOGIN;
   END IF;
END
\$\$;"
    DATABASE=fdw_target sql postgres 'CREATE SCHEMA test_fdw;'
    DATABASE=fdw_target sql postgres 'CREATE TABLE test_fdw.foo (a int);'
    DATABASE=fdw_target sql postgres 'INSERT INTO test_fdw.foo (a) values (42);'
    DATABASE=fdw_target sql postgres 'CREATE TABLE test_fdw.foo2 (a int);'
    DATABASE=fdw_target sql postgres 'INSERT INTO test_fdw.foo2 (a) values (42);'
    DATABASE=fdw_target sql postgres "CREATE USER fdw_user WITH PASSWORD 'foobarino';"
    DATABASE=fdw_target sql postgres 'GRANT USAGE ON SCHEMA test_fdw TO fdw_user;'
    DATABASE=fdw_target sql postgres 'GRANT SELECT ON TABLE test_fdw.foo TO fdw_user;'
    DATABASE=fdw_target sql postgres 'GRANT SELECT ON TABLE test_fdw.foo2 TO fdw_user;'
    DATABASE=fdw_target sql postgres 'GRANT SELECT ON cdb_tablemetadata_text TO fdw_user;'

    DATABASE=fdw_target sql postgres "SELECT cdb_tablemetadatatouch('test_fdw.foo'::regclass);"
    DATABASE=fdw_target sql postgres "SELECT cdb_tablemetadatatouch('test_fdw.foo2'::regclass);"

    # Add PGPORT to conf if it is set
    PORT_SPEC=""
    if [[ "$PGPORT" != "" ]] ; then
        PORT_SPEC=", \"port\": \"$PGPORT\""
    fi
    sql postgres "SELECT cartodb.CDB_Conf_SetConf('fdws', '{\"test_fdw\": {\"server\": {\"host\": \"localhost\", \"dbname\": \"fdw_target\" $PORT_SPEC },
                                           \"users\": {\"public\": {\"user\": \"fdw_user\", \"password\": \"foobarino\"}}}}')"

    sql postgres "SELECT cartodb._CDB_Setup_FDW('test_fdw')"

    sql postgres "SHOW server_version_num"
    if [ "$RESULT" -gt 90499 ]
    then
        sql postgres "SELECT cartodb.CDB_Add_Remote_Table('test_fdw', 'foo')"
        sql postgres "SELECT * from test_fdw.foo;"
    else
        echo "NOTICE: PostgreSQL version is less than 9.5 ($RESULT). Skipping CDB_Add_Remote_Table."
        sql postgres "CREATE FOREIGN TABLE test_fdw.foo (a int) SERVER test_fdw OPTIONS (table_name 'foo', schema_name 'test_fdw')"
    fi

    sql postgres "SELECT n.nspname,
  c.relname,
  s.srvname FROM pg_catalog.pg_foreign_table ft
  INNER JOIN pg_catalog.pg_class c ON c.oid = ft.ftrelid
  INNER JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  INNER JOIN pg_catalog.pg_foreign_server s ON s.oid = ft.ftserver
ORDER BY 1, 2" should "test_fdw|cdb_tablemetadata|test_fdw
test_fdw|foo|test_fdw"

    sql postgres "SELECT cartodb.CDB_Get_Foreign_Updated_At('test_fdw.foo'::regclass) < NOW()" should 't'

    sql postgres "SELECT a from test_fdw.foo LIMIT 1;" should 42

    # Check function CDB_QueryTables_Updated_At
    sql postgres 'CREATE TABLE local (b int);'
    sql postgres 'INSERT INTO local (b) VALUES (43);'
    sql postgres "SELECT cdb_tablemetadatatouch('public.local'::regclass);"
    local query='$query$ SELECT * FROM test_fdw.foo, local $query$::text'
    sql postgres "SELECT dbname, schema_name, table_name FROM cartodb.CDB_QueryTables_Updated_At(${query}) ORDER BY dbname;" should 'fdw_target|test_fdw|foo
test_extension|public|local'
    sql postgres "SELECT table_name FROM cartodb.CDB_QueryTables_Updated_At(${query}) order by updated_at;" should 'foo
local'

    # Check function CDB_Last_Updated_Time
    sql postgres "SELECT cartodb.CDB_Last_Updated_Time('{test_fdw.foo,public.local}'::text[]) < now()" should 't'
    sql postgres "SELECT cartodb.CDB_Last_Updated_Time('{test_fdw.foo,public.local}'::text[]) > (now() - interval '1 minute')" should 't'

    # Check we quote names on output as needed (as CDB_QueryTablesText does)
    sql postgres 'CREATE TABLE "local-table-with-dashes" (c int)';
    sql postgres 'INSERT INTO "local-table-with-dashes" (c) VALUES (44)';
    sql postgres "SELECT cdb_tablemetadatatouch('public.local-table-with-dashes'::regclass);"
    query='$query$ SELECT * FROM test_fdw.foo, local, public."local-table-with-dashes" $query$::text'
    sql postgres "SELECT dbname, schema_name, table_name FROM cartodb.CDB_QueryTables_Updated_At(${query}) ORDER BY dbname, schema_name, table_name;" should 'fdw_target|test_fdw|foo
test_extension|public|local
test_extension|public|"local-table-with-dashes"'

    # Check CDB_Last_Updated_Time supports quoted identifiers
    sql postgres "SELECT cartodb.CDB_Last_Updated_Time(ARRAY['test_extension.public.\"local-table-with-dashes\"']::text[]) < now()" should 't'
    sql postgres "SELECT cartodb.CDB_Last_Updated_Time(ARRAY['test_extension.public.\"local-table-with-dashes\"']::text[]) > (now() - interval '1 minute')" should 't'

    DATABASE=fdw_target sql postgres 'REVOKE USAGE ON SCHEMA test_fdw FROM fdw_user;'
    DATABASE=fdw_target sql postgres 'REVOKE SELECT ON test_fdw.foo FROM fdw_user;'
    DATABASE=fdw_target sql postgres 'REVOKE SELECT ON test_fdw.foo2 FROM fdw_user;'
    DATABASE=fdw_target sql postgres 'REVOKE SELECT ON cdb_tablemetadata_text FROM fdw_user;'
    DATABASE=fdw_target sql postgres 'DROP ROLE fdw_user;'

    sql postgres "select pg_terminate_backend(pid) from pg_stat_activity where datname='fdw_target';"
    DATABASE=fdw_target tear_down_database
}

function test_cdb_catalog_basic_node() {
    DEF="'{\"type\":\"buffer\",\"source\":\"b2db66bc7ac02e135fd20bbfef0fdd81b2d15fad\",\"radio\":10000}'"
    sql postgres "INSERT INTO cartodb.cdb_analysis_catalog (node_id, analysis_def) VALUES ('1bbc4c41ea7c9d3a7dc1509727f698b7', ${DEF}::json)"
    sql postgres "SELECT status from cartodb.cdb_analysis_catalog where node_id = '1bbc4c41ea7c9d3a7dc1509727f698b7'" should 'pending'
    sql postgres "DELETE FROM cartodb.cdb_analysis_catalog"
}

#################################################### TESTS END HERE ####################################################

run_tests $@

exit ${OK}
