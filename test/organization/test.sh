#!/bin/sh

#
# It is expected that you run this script
# as a PostgreSQL superuser, for example:
#
#   PGUSER=postgres bash ./test.sh
#

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
        echo -e "FAILED TO EXECUTE QUERY: \033[0;33m${QUERY}\033[0m"
        if [[ "$3" != "fails" ]]
        then
            log_error "${QUERY}"
            OK=1
        fi
    else
        if [[ "$3" == "fails" ]]
        then
            log_error "QUERY: '${QUERY}' was expected to fail and it did not fail"
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
    sql "SELECT cartodb.CDB_Organization_Create_Member('${ROLE}')"
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


function setup() {
    ${CMD} -c "CREATE DATABASE ${DATABASE}"
    sql "CREATE SCHEMA cartodb;"
    sql "GRANT USAGE ON SCHEMA cartodb TO public;"

    log_info "########################### BOOTSTRAP ###########################"
    ${CMD} -d ${DATABASE} -f scripts-available/CDB_Organizations.sql


    log_info "############################# SETUP #############################"
    create_role_and_schema cdb_testmember_1
    create_role_and_schema cdb_testmember_2

    create_table cdb_testmember_1 foo
    sql cdb_testmember_1 'INSERT INTO cdb_testmember_1.foo VALUES (1), (2), (3), (4), (5);'
    sql cdb_testmember_1 'SELECT * FROM cdb_testmember_1.foo;'

    create_table cdb_testmember_2 bar
    sql cdb_testmember_2 'INSERT INTO bar VALUES (1), (2), (3), (4), (5);'
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
    sql cdb_testmember_2 'SELECT count(*) FROM cdb_testmember_1.foo;' fails
}

function test_member_1_cannot_grant_read_permission_to_other_schema_than_its_one() {
    sql cdb_testmember_1 "SELECT * FROM cartodb.CDB_Organization_Add_Table_Read_Permission('cdb_testmember_2', 'foo', 'cdb_testmember_2')" fails
}

function test_member_1_grants_read_permission_and_member_2_can_read() {
    sql cdb_testmember_1 "SELECT * FROM cartodb.CDB_Organization_Add_Table_Read_Permission('cdb_testmember_1', 'foo', 'cdb_testmember_2')"
    sql cdb_testmember_2 'SELECT count(*) FROM cdb_testmember_1.foo;' should 5
    sql cdb_testmember_1 'SELECT count(*) FROM cdb_testmember_2.bar;' fails
}

function test_member_2_cannot_add_table_to_member_1_schema_after_table_permission_added() {
    sql cdb_testmember_1 "SELECT * FROM cartodb.CDB_Organization_Add_Table_Read_Permission('cdb_testmember_1', 'foo', 'cdb_testmember_2')"
    sql cdb_testmember_2 "CREATE TABLE cdb_testmember_1.bar ( a int );" fails
}

function test_grant_read_permission_between_two_members() {
    sql cdb_testmember_1 "SELECT * FROM cartodb.CDB_Organization_Add_Table_Read_Permission('cdb_testmember_1', 'foo', 'cdb_testmember_2')"
    sql cdb_testmember_2 "SELECT * FROM cartodb.CDB_Organization_Add_Table_Read_Permission('cdb_testmember_2', 'bar', 'cdb_testmember_1')"
    sql cdb_testmember_2 'SELECT count(*) FROM cdb_testmember_1.foo;' should 5
    sql cdb_testmember_1 'SELECT count(*) FROM cdb_testmember_2.bar;' should 5
}

function test_member_2_cannot_write_to_member_1_table() {
    sql cdb_testmember_2 'INSERT INTO cdb_testmember_1.foo VALUES (5), (6), (7), (8), (9);' fails
}

function test_member_1_cannot_grant_read_write_permission_to_other_schema_than_its_one() {
    sql cdb_testmember_1 "SELECT * FROM cartodb.CDB_Organization_Add_Table_Read_Write_Permission('cdb_testmember_2', 'foo', 'cdb_testmember_2')" fails
}

function test_member_2_can_write_to_member_1_table_after_write_permission_is_added() {
    sql cdb_testmember_1 "SELECT * FROM cartodb.CDB_Organization_Add_Table_Read_Write_Permission('cdb_testmember_1', 'foo', 'cdb_testmember_2')"
    sql cdb_testmember_2 'INSERT INTO cdb_testmember_1.foo VALUES (5), (6), (7), (8), (9);'
    sql cdb_testmember_1 'SELECT count(*) FROM cdb_testmember_1.foo;' should 10
    sql cdb_testmember_2 'SELECT count(*) FROM cdb_testmember_1.foo;' should 10
}

function test_member_1_removes_access_and_member_2_can_no_longer_query_the_table() {
    sql cdb_testmember_1 "SELECT * FROM cartodb.CDB_Organization_Add_Table_Read_Permission('cdb_testmember_1', 'foo', 'cdb_testmember_2')"
    sql cdb_testmember_2 'SELECT count(*) FROM cdb_testmember_1.foo;' should 5
    sql cdb_testmember_1 "SELECT * FROM cartodb.CDB_Organization_Remove_Access_Permission('cdb_testmember_1', 'foo', 'cdb_testmember_2')"
    sql cdb_testmember_2 'SELECT * FROM cdb_testmember_1.foo;' fails
}

function test_member_1_removes_access_and_member_2_can_no_longer_write_to_the_table() {
    sql cdb_testmember_1 "SELECT * FROM cartodb.CDB_Organization_Add_Table_Read_Write_Permission('cdb_testmember_1', 'foo', 'cdb_testmember_2')"
    sql cdb_testmember_2 'INSERT INTO cdb_testmember_1.foo VALUES (5), (6), (7), (8), (9);'
    sql cdb_testmember_1 "SELECT * FROM cartodb.CDB_Organization_Remove_Access_Permission('cdb_testmember_1', 'foo', 'cdb_testmember_2')"
    sql cdb_testmember_2 'INSERT INTO cdb_testmember_1.foo VALUES (5), (6), (7), (8), (9);' fails
}

function test_giving_permissions_to_two_tables_and_removing_from_first_table_should_not_remove_from_second() {
    #### test setup
    # create an extra table for cdb_testmember_1
    create_table cdb_testmember_1 foo_2
    sql cdb_testmember_1 'INSERT INTO cdb_testmember_1.foo_2 VALUES (1), (2), (3), (4), (5);'
    sql cdb_testmember_1 'SELECT * FROM cdb_testmember_1.foo_2;'

    # gives read permission to both tables
    sql cdb_testmember_1 "SELECT * FROM cartodb.CDB_Organization_Add_Table_Read_Permission('cdb_testmember_1', 'foo', 'cdb_testmember_2')"
    sql cdb_testmember_1 "SELECT * FROM cartodb.CDB_Organization_Add_Table_Read_Permission('cdb_testmember_1', 'foo_2', 'cdb_testmember_2')"

    # cdb_testmember_2 has access to both tables
    sql cdb_testmember_2 'SELECT count(*) FROM cdb_testmember_1.foo;' should 5
    sql cdb_testmember_2 'SELECT count(*) FROM cdb_testmember_1.foo_2;' should 5

    # cdb_testmember_1 removes access to foo table
    sql cdb_testmember_1 "SELECT * FROM cartodb.CDB_Organization_Remove_Access_Permission('cdb_testmember_1', 'foo', 'cdb_testmember_2')"

    # cdb_testmember_2 should have access to foo_2 table but not to table foo
    sql cdb_testmember_2 'SELECT count(*) FROM cdb_testmember_1.foo;' fails
    sql cdb_testmember_2 'SELECT count(*) FROM cdb_testmember_1.foo_2;' should 5


    #### test tear down
    sql cdb_testmember_1 'DROP TABLE cdb_testmember_1.foo_2;'
}

function test_cdb_org_member_role_allows_reading_to_all_users_without_explicit_permission() {
    sql cdb_testmember_2 'SELECT count(*) FROM cdb_testmember_1.foo;' fails
    sql cdb_testmember_1 "SELECT cartodb.CDB_Organization_Add_Table_Organization_Read_Permission('cdb_testmember_1', 'foo');"
    sql cdb_testmember_2 'SELECT count(*) FROM cdb_testmember_1.foo;' should 5
}

function test_user_can_read_when_it_has_permission_after_organization_permission_is_removed() {
    create_role_and_schema cdb_testmember_3

    # shares with cdb_testmember_2 and can read but cdb_testmember_3 cannot
    sql cdb_testmember_1 "SELECT * FROM cartodb.CDB_Organization_Add_Table_Read_Permission('cdb_testmember_1', 'foo', 'cdb_testmember_2')"
    sql cdb_testmember_2 'SELECT count(*) FROM cdb_testmember_1.foo;' should 5
    sql cdb_testmember_3 'SELECT count(*) FROM cdb_testmember_1.foo;' fails

    # granting to organization allows to read to both: cdb_testmember_2 and cdb_testmember_3
    sql cdb_testmember_1 "SELECT cartodb.CDB_Organization_Add_Table_Organization_Read_Permission('cdb_testmember_1', 'foo');"
    sql cdb_testmember_2 'SELECT count(*) FROM cdb_testmember_1.foo;' should 5
    sql cdb_testmember_3 'SELECT count(*) FROM cdb_testmember_1.foo;' should 5

    # removing access from organization should keep permission on cdb_testmember_2 but drop it to cdb_testmember_3
    sql cdb_testmember_1 "SELECT cartodb.CDB_Organization_Remove_Organization_Access_Permission('cdb_testmember_1', 'foo');"
    sql cdb_testmember_2 'SELECT count(*) FROM cdb_testmember_1.foo;' should 5
    sql cdb_testmember_3 'SELECT count(*) FROM cdb_testmember_1.foo;' fails

    drop_role_and_schema cdb_testmember_3
}

#################################################### TESTS END HERE ####################################################



run_tests $@

exit ${OK}
