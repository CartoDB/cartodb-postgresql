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
    sql "DROP SCHEMA \"${ROLE}\";"
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


function setup() {
    ${CMD} -c "CREATE DATABASE ${DATABASE}"
    sql "CREATE SCHEMA cartodb;"
    sql "GRANT USAGE ON SCHEMA cartodb TO public;"
    sql "CREATE EXTENSION postgis;"

    log_info "########################### BOOTSTRAP ###########################"
    ${CMD} -d ${DATABASE} -f scripts-available/CDB_Organizations.sql
    # trick to allow forcing a schema when loading SQL files (see: http://bit.ly/1HeLnhL)
    ${CMD} -d ${DATABASE} -f test/extension/run_at_cartodb_schema.sql


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

function tear_down() {
    log_info "########################### USER TEAR DOWN ###########################"
    sql cdb_testmember_1 "SELECT * FROM cartodb.CDB_Organization_Remove_Access_Permission('cdb_testmember_1', 'foo', 'cdb_testmember_2');"
    sql cdb_testmember_2 "SELECT * FROM cartodb.CDB_Organization_Remove_Access_Permission('cdb_testmember_2', 'bar', 'cdb_testmember_1');"

    sql cdb_testmember_1 'DROP TABLE cdb_testmember_1.foo;'
    sql cdb_testmember_2 'DROP TABLE cdb_testmember_2.bar;'

    sql "DROP SCHEMA cartodb CASCADE"

    log_info "########################### TEAR DOWN ###########################"
    sql 'DROP SCHEMA cdb_testmember_1;'
    sql 'DROP SCHEMA cdb_testmember_2;'

    sql "REVOKE CONNECT ON DATABASE \"${DATABASE}\" FROM cdb_testmember_1;"
    sql "REVOKE CONNECT ON DATABASE \"${DATABASE}\" FROM cdb_testmember_2;"

    sql 'DROP ROLE cdb_testmember_1;'
    sql 'DROP ROLE cdb_testmember_2;'

    ${CMD} -c "DROP DATABASE ${DATABASE}"
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

#################################################### TESTS END HERE ####################################################

run_tests $@

exit ${OK}
