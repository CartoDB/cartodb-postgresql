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
    local FAILED_TESTS=()

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
    sql cdb_testmember_2 'DELETE FROM cdb_testmember_1.foo where a = 9;'
    sql cdb_testmember_1 'SELECT count(*) FROM cdb_testmember_1.foo;' should 9
    sql cdb_testmember_2 'SELECT count(*) FROM cdb_testmember_1.foo;' should 9
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

function test_cdb_querytables_returns_schema_and_table_name() {
    sql "CREATE EXTENSION plpythonu;"
    ${CMD} -d ${DATABASE} -f scripts-available/CDB_QueryStatements.sql
    ${CMD} -d ${DATABASE} -f scripts-available/CDB_QueryTables.sql
    sql cdb_testmember_1 "select * from CDB_QueryTables('select * from foo');" should "{cdb_testmember_1.foo}"
}

function test_cdb_querytables_returns_schema_and_table_name_for_several_schemas() {
    sql "CREATE EXTENSION plpythonu;"
    ${CMD} -d ${DATABASE} -f scripts-available/CDB_QueryStatements.sql
    ${CMD} -d ${DATABASE} -f scripts-available/CDB_QueryTables.sql
    sql postgres "select * from CDB_QueryTables('select * from cdb_testmember_1.foo, cdb_testmember_2.bar');" should "{cdb_testmember_1.foo,cdb_testmember_2.bar}"
}

function test_cdb_querytables_does_not_return_functions_as_part_of_the_resultset() {
    sql "CREATE EXTENSION plpythonu;"
    ${CMD} -d ${DATABASE} -f scripts-available/CDB_QueryStatements.sql
    ${CMD} -d ${DATABASE} -f scripts-available/CDB_QueryTables.sql
    sql postgres "select * from CDB_QueryTables('select * from cdb_testmember_1.foo, cdb_testmember_2.bar, plainto_tsquery(''foo'')');" should "{cdb_testmember_1.foo,cdb_testmember_2.bar}"
}

function test_cdb_usertables_should_work_with_orgusers() {
    sql "CREATE ROLE publicuser LOGIN"
    sql "GRANT USAGE ON SCHEMA cartodb TO publicuser;"
    ${CMD} -d ${DATABASE} -f scripts-available/CDB_UserTables.sql
    sql cdb_testmember_1 "CREATE TABLE test_perms_pub (a int)"
    sql cdb_testmember_1 "CREATE TABLE test_perms_priv (a int)"
    sql cdb_testmember_1 "GRANT SELECT ON TABLE test_perms_pub TO publicuser"
    sql publicuser "SELECT count(*) FROM CDB_UserTables('all')" should 1
    sql publicuser "SELECT count(*) FROM CDB_UserTables('public')" should 1
    sql publicuser "SELECT count(*) FROM CDB_UserTables('private')" should 0
    # the following tests are for https://github.com/CartoDB/cartodb-postgresql/issues/98
    #sql cdb_testmember_2 "SELECT count(*) FROM CDB_UserTables('all')" should 1
    #sql cdb_testmember_2 "SELECT count(*) FROM CDB_UserTables('public')" should 1
    #sql cdb_testmember_2 "SELECT count(*) FROM CDB_UserTables('private')" should 0
}


#################################################### TESTS END HERE ####################################################



run_tests $@

exit ${OK}
