#!/bin/sh

DATABASE=test_organizations
CMD='echo psql'
CMD=psql

OK=0

function sql() {
    local ROLE
    local QUERY
    if [[ $# -ge 2 ]]
    then
        ROLE="$1"
        QUERY="$2"
    else
        ROLE="postgres"
        QUERY="$1"
    fi

    log_debug "Executing query '${QUERY}' as ${ROLE}"

    RESULT=`${CMD} -U "${ROLE}" ${DATABASE} -c "${QUERY}" -A -t`
    CODERESULT=$?

    echo ${RESULT}
    echo

    if [[ ${CODERESULT} -ne 0 ]]
    then
        echo -e "FAILED TO EXECUTE QUERY: \033[0;33m${QUERY}\033[0m"
        if [[ "$3" != "fails" ]]
        then
            OK=1
        fi
    else
        if [[ "$3" == "fails" ]]
        then
            echo -e "QUERY: \033[0;33m${QUERY}\033[0m was expected to fail and it did not fail"
            OK=1
        fi
    fi

    if [[ "$3" == "should" ]]
    then
        if [[ "${RESULT}" != "$4" ]]
        then
            log_error "QUERY '${QUERY}' expected result '${4}' but got '${RESULT}'"
            OK=1
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

function _log() {
    echo -e "\033[$1$2\033[0m"
}

# '############################ HELPERS #############################'
function create_role_and_schema() {
    local ROLE=$1
    sql "CREATE ROLE ${ROLE} LOGIN;"
    sql "GRANT CONNECT ON DATABASE \"${DATABASE}\" TO ${ROLE};"
    sql "CREATE SCHEMA ${ROLE} AUTHORIZATION ${ROLE};"
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


function setup() {
    ${CMD} -U postgres -c "CREATE DATABASE ${DATABASE}"
    sql "CREATE SCHEMA cartodb AUTHORIZATION postgres;"
    sql "GRANT USAGE ON SCHEMA cartodb TO public;"

    log_info "########################### BOOTSTRAP ###########################"
    ${CMD} -U postgres -d ${DATABASE} -f scripts-available/CDB_Organizations.sql


    log_info "############################# SETUP #############################"
    create_role_and_schema member_1
    create_role_and_schema member_2

    create_table member_1 foo
    sql member_1 'INSERT INTO member_1.foo VALUES (1), (2), (3), (4), (5);'
    sql member_1 'SELECT * FROM member_1.foo;'

    create_table member_2 bar
    sql member_2 'INSERT INTO bar VALUES (1), (2), (3), (4), (5);'
    sql member_2 'SELECT * FROM member_2.bar;'
}

function tear_down() {
    log_info "########################### USER TEAR DOWN ###########################"
    sql member_1 "SELECT * FROM cartodb.CDB_Organization_Remove_Access_Permission('foo', 'member_2');"
    sql member_2 "SELECT * FROM cartodb.CDB_Organization_Remove_Access_Permission('bar', 'member_1');"

    sql member_1 'DROP TABLE member_1.foo;'
    sql member_2 'DROP TABLE member_2.bar;'

    sql "DROP SCHEMA cartodb CASCADE"

    log_info "########################### TEAR DOWN ###########################"
    sql 'DROP SCHEMA member_1;'
    sql "REVOKE CONNECT ON DATABASE \"${DATABASE}\" FROM member_1;"
    sql 'DROP ROLE member_1;'

    sql 'DROP SCHEMA member_2;'
    sql "REVOKE CONNECT ON DATABASE \"${DATABASE}\" FROM member_2;"
    sql 'DROP ROLE member_2;'

    ${CMD} -U postgres -c "DROP DATABASE ${DATABASE}"
}

function run_tests() {

    local TESTS
    if [[ $# -ge 1 ]]
    then
        TESTS="$@"
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
        setup
        eval ${t}
        tear_down
    done
}



#################################################### TESTS GO HERE ####################################################

function test_member_2_cannot_read_without_permission() {
    sql member_2 'SELECT count(*) FROM member_1.foo;' fails
}

function test_member_1_grants_read_permission_and_member_2_can_read() {
    sql member_1 "SELECT * FROM cartodb.CDB_Organization_Add_Table_Read_Permission('foo', 'member_2')"
    sql member_2 'SELECT count(*) FROM member_1.foo;' should 5
    sql member_1 'SELECT count(*) FROM member_2.bar;' fails
}

function test_member_2_cannot_add_table_to_member_1_schema_after_table_permission_added() {
    sql member_1 "SELECT * FROM cartodb.CDB_Organization_Add_Table_Read_Permission('foo', 'member_2')"
    sql member_2 "CREATE TABLE member_1.bar ( a int );" fails
}

function test_grant_read_permission_between_two_members() {
    sql member_1 "SELECT * FROM cartodb.CDB_Organization_Add_Table_Read_Permission('foo', 'member_2')"
    sql member_2 "SELECT * FROM cartodb.CDB_Organization_Add_Table_Read_Permission('bar', 'member_1')"
    sql member_2 'SELECT count(*) FROM member_1.foo;' should 5
    sql member_1 'SELECT count(*) FROM member_2.bar;' should 5
}

function test_member_2_cannot_write_to_member_1_table() {
    sql member_2 'INSERT INTO member_1.foo VALUES (5), (6), (7), (8), (9);' fails
}

function test_member_2_can_write_to_member_1_table_after_write_permission_is_added() {
    sql member_1 "SELECT * FROM cartodb.CDB_Organization_Add_Table_Read_Write_Permission('foo', 'member_2')"
    sql member_2 'INSERT INTO member_1.foo VALUES (5), (6), (7), (8), (9);'
    sql member_1 'SELECT count(*) FROM member_1.foo;' should 10
    sql member_2 'SELECT count(*) FROM member_1.foo;' should 10
}

function test_member_1_removes_access_and_member_2_can_no_longer_query_the_table() {
    sql member_1 "SELECT * FROM cartodb.CDB_Organization_Add_Table_Read_Permission('foo', 'member_2')"
    sql member_2 'SELECT count(*) FROM member_1.foo;' should 5
    sql member_1 "SELECT * FROM cartodb.CDB_Organization_Remove_Access_Permission('foo', 'member_2')"
    sql member_2 'SELECT * FROM member_1.foo;' fails
}

function test_member_1_removes_access_and_member_2_can_no_longer_write_to_the_table() {
    sql member_1 "SELECT * FROM cartodb.CDB_Organization_Add_Table_Read_Write_Permission('foo', 'member_2')"
    sql member_2 'INSERT INTO member_1.foo VALUES (5), (6), (7), (8), (9);'
    sql member_1 "SELECT * FROM cartodb.CDB_Organization_Remove_Access_Permission('foo', 'member_2')"
    sql member_2 'INSERT INTO member_1.foo VALUES (5), (6), (7), (8), (9);' fails
}

#################################################### TESTS END HERE ####################################################



run_tests $@

exit ${OK}