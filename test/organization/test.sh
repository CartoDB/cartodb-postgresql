#!/bin/sh

#
# It is expected that you run this script
# as a PostgreSQL superuser, for example:
#
#   PGUSER=postgres bash ./test.sh
#

DATABASE=test_organizations
CMD=psql
SED=sed

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
    ERROR_OUTPUT_FILE='/tmp/test_error.log'
    if [[ $# -ge 2 ]]
    then
        ROLE="$1"
        QUERY="$2"
    else
        QUERY="$1"
    fi

    if [ -n "${ROLE}" ]; then
        log_debug "Executing query '${QUERY}' as ${ROLE}"
        RESULT=`${CMD} -U "${ROLE}" ${DATABASE} -c "${QUERY}" -A -t 2>"${ERROR_OUTPUT_FILE}"`
    else
        log_debug "Executing query '${QUERY}'"
        RESULT=`${CMD} ${DATABASE} -c "${QUERY}" -A -t 2>"${ERROR_OUTPUT_FILE}"`
    fi
    CODERESULT=$?
    ERROR_OUTPUT=`cat "${ERROR_OUTPUT_FILE}"`
    rm ${ERROR_OUTPUT_FILE}

    echo -n "> Code Result: "
    echo -n ${CODERESULT}
    echo -n "; Result: "
    echo -n ${RESULT}
    echo -n "; Error output: "
    echo -n ${ERROR_OUTPUT}

    # Some warnings should actually be failures
    if [[ ${CODERESULT} == "0" ]]
    then
        case "${ERROR_OUTPUT}" in
            WARNING:*no*privileges*were*granted*for*)
                echo -n "FAILED BECAUSE OF PRIVILEGES GRANTING WARNING"
                CODERESULT=1
            ;;
            WARNING:*no*privileges*could*be*revoked*for*)
                echo -n "FAILED BECAUSE OF PRIVILEGES REVOKING WARNING"
                CODERESULT=1
            ;;
            *) ;;
        esac
        echo -n "; Code result after warnings: "
        echo -n ${CODERESULT}
    fi
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
    sql "ALTER ROLE ${ROLE} SET search_path TO ${ROLE},cartodb,public;"
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

function truncate_table() {
    if [[ $# -ne 2 ]]
    then
        log_error "truncate_table requires two arguments: role and table_name"
        exit 1
    fi
    local ROLE="$1"
    local TABLENAME="$2"
    sql ${ROLE} "TRUNCATE TABLE ${ROLE}.${TABLENAME};"
}


function setup() {
    ${CMD} -c "CREATE DATABASE ${DATABASE}"
    ${CMD} -c "ALTER DATABASE ${DATABASE} SET search_path = public, cartodb;"
    sql "CREATE EXTENSION cartodb CASCADE;"
    ${CMD} -c "ALTER DATABASE ${DATABASE} SET search_path = public, cartodb;"


    log_info "############################# SETUP #############################"
    create_role_and_schema cdb_org_admin
    sql "SELECT cartodb.CDB_Organization_AddAdmin('cdb_org_admin');"
    create_role_and_schema cdb_testmember_1
    create_role_and_schema cdb_testmember_2
    sql postgres "DO
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
    sql "GRANT CONNECT ON DATABASE \"${DATABASE}\" TO publicuser;"

    create_table cdb_testmember_1 foo
    create_table cdb_testmember_2 bar

    sql "SELECT cartodb.CDB_Group_CreateGroup('group_a_tmp')"
    sql "SELECT cartodb.CDB_Group_RenameGroup('group_a_tmp', 'group_a')"

    sql "SELECT cartodb.CDB_Group_AddUsers('group_a', ARRAY['cdb_testmember_1'])"

    sql "SELECT cartodb.CDB_Group_CreateGroup('group_b')"
}


function tear_down() {
    log_info "########################### USER TEAR DOWN ###########################"
    sql cdb_testmember_1 "SELECT * FROM cartodb.CDB_Organization_Remove_Access_Permission('cdb_testmember_1', 'foo', 'cdb_testmember_2');"
    sql cdb_testmember_2 "SELECT * FROM cartodb.CDB_Organization_Remove_Access_Permission('cdb_testmember_2', 'bar', 'cdb_testmember_1');"

    sql cdb_testmember_1 'DROP TABLE cdb_testmember_1.foo;'
    sql cdb_testmember_2 'DROP TABLE cdb_testmember_2.bar;'

    sql "select cartodb.CDB_Group_DropGroup('group_b')"

    sql "SELECT cartodb.CDB_Group_RemoveUsers('group_a', ARRAY['cdb_testmember_1'])"

    sql "select cartodb.CDB_Group_DropGroup('group_a')"
    sql "SELECT cartodb.CDB_Organization_RemoveAdmin('cdb_org_admin');"

    sql "DROP SCHEMA cartodb CASCADE"

    log_info "########################### TEAR DOWN ###########################"
    sql 'DROP SCHEMA cdb_testmember_1;'
    sql 'DROP SCHEMA cdb_testmember_2;'
    sql 'DROP SCHEMA cdb_org_admin;'

    sql "REVOKE CONNECT ON DATABASE \"${DATABASE}\" FROM cdb_testmember_1;"
    sql "REVOKE CONNECT ON DATABASE \"${DATABASE}\" FROM cdb_testmember_2;"
    sql "REVOKE CONNECT ON DATABASE \"${DATABASE}\" FROM publicuser;"
    sql "REVOKE CONNECT ON DATABASE \"${DATABASE}\" FROM cdb_org_admin;"

    sql 'DROP ROLE cdb_testmember_1;'
    sql 'DROP ROLE cdb_testmember_2;'
    sql 'DROP ROLE cdb_org_admin;'

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

    setup
    for t in ${TESTS}
    do
#         if [[ ${t} != "test_cdb_usertables_should_work_with_orgusers" ]]; then
#             continue;
#         fi
        echo "####################################################################"
        echo "#"
        echo "# Running: ${t}"
        echo "#"
        echo "####################################################################"
        clear_partial_result
        log_info "############################# TESTS #############################"
        eval ${t}
        if [[ ${PARTIALOK} -ne 0 ]]
        then
            FAILED_TESTS+=(${t})
        fi
    done
    tear_down

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
    sql cdb_testmember_1 'INSERT INTO cdb_testmember_1.foo VALUES (5), (6), (7), (8), (9);'
    sql cdb_testmember_1 "SELECT * FROM cartodb.CDB_Organization_Add_Table_Read_Permission('cdb_testmember_1', 'foo', 'cdb_testmember_2')"
    sql cdb_testmember_2 'SELECT count(*) FROM cdb_testmember_1.foo;' should 5
    sql cdb_testmember_1 'SELECT count(*) FROM cdb_testmember_2.bar;' fails

    # Cleanup
    truncate_table cdb_testmember_1 foo
    sql cdb_testmember_1 "SELECT * FROM cartodb.CDB_Organization_Remove_Access_Permission('cdb_testmember_1', 'foo', 'cdb_testmember_2')"
}

function test_member_2_cannot_add_table_to_member_1_schema_after_table_permission_added() {
    sql cdb_testmember_1 "SELECT * FROM cartodb.CDB_Organization_Add_Table_Read_Permission('cdb_testmember_1', 'foo', 'cdb_testmember_2')"
    sql cdb_testmember_2 "CREATE TABLE cdb_testmember_1.bar ( a int );" fails
}

function test_grant_read_permission_between_two_members() {
    sql cdb_testmember_1 'INSERT INTO cdb_testmember_1.foo VALUES (5), (6), (7), (8), (9);'
    sql cdb_testmember_2 'INSERT INTO cdb_testmember_2.bar VALUES (5), (6), (7), (8), (9);'
    sql cdb_testmember_1 "SELECT * FROM cartodb.CDB_Organization_Add_Table_Read_Permission('cdb_testmember_1', 'foo', 'cdb_testmember_2')"
    sql cdb_testmember_2 "SELECT * FROM cartodb.CDB_Organization_Add_Table_Read_Permission('cdb_testmember_2', 'bar', 'cdb_testmember_1')"
    sql cdb_testmember_2 'SELECT count(*) FROM cdb_testmember_1.foo;' should 5
    sql cdb_testmember_1 'SELECT count(*) FROM cdb_testmember_2.bar;' should 5

    # Cleanup
    truncate_table cdb_testmember_1 foo
    truncate_table cdb_testmember_2 bar
    sql cdb_testmember_1 "SELECT * FROM cartodb.CDB_Organization_Remove_Access_Permission('cdb_testmember_1', 'foo', 'cdb_testmember_2')"
    sql cdb_testmember_2 "SELECT * FROM cartodb.CDB_Organization_Remove_Access_Permission('cdb_testmember_2', 'bar', 'cdb_testmember_1')"
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
    sql cdb_testmember_1 'SELECT count(*) FROM cdb_testmember_1.foo;' should 5
    sql cdb_testmember_2 'SELECT count(*) FROM cdb_testmember_1.foo;' should 5
    sql cdb_testmember_2 'DELETE FROM cdb_testmember_1.foo where a = 9;'
    sql cdb_testmember_1 'SELECT count(*) FROM cdb_testmember_1.foo;' should 4
    sql cdb_testmember_2 'SELECT count(*) FROM cdb_testmember_1.foo;' should 4

    # Cleanup
    truncate_table cdb_testmember_1 foo
    sql cdb_testmember_1 "SELECT * FROM cartodb.CDB_Organization_Remove_Access_Permission('cdb_testmember_1', 'foo', 'cdb_testmember_2')"
}

function test_member_2_can_write_to_member_1_table_and_sequence_after_write_permission_is_added() {
    sql cdb_testmember_1 "ALTER TABLE cdb_testmember_1.foo ADD cartodb_id SERIAL NOT NULL UNIQUE;"

    sql cdb_testmember_1 "SELECT * FROM cartodb.CDB_Organization_Add_Table_Read_Write_Permission('cdb_testmember_1', 'foo', 'cdb_testmember_2')"
    sql cdb_testmember_2 'INSERT INTO cdb_testmember_1.foo VALUES (5), (6), (7), (8), (9);'
    sql cdb_testmember_1 'SELECT count(*) FROM cdb_testmember_1.foo;' should 5
    sql cdb_testmember_2 'SELECT count(*) FROM cdb_testmember_1.foo;' should 5
    sql cdb_testmember_2 'DELETE FROM cdb_testmember_1.foo where a = 9;'
    sql cdb_testmember_1 'SELECT count(*) FROM cdb_testmember_1.foo;' should 4
    sql cdb_testmember_2 'SELECT count(*) FROM cdb_testmember_1.foo;' should 4

    sql cdb_testmember_1 "ALTER TABLE cdb_testmember_1.foo DROP cartodb_id;"

    # Cleanup
    truncate_table cdb_testmember_1 foo
    sql cdb_testmember_1 "SELECT * FROM cartodb.CDB_Organization_Remove_Access_Permission('cdb_testmember_1', 'foo', 'cdb_testmember_2')"
}

function test_member_2_can_write_to_member_1_table_with_non_sequence_cartodb_id_after_write_permission_is_added() {
    sql cdb_testmember_1 "ALTER TABLE cdb_testmember_1.foo ADD cartodb_id INTEGER;"

    sql cdb_testmember_1 "SELECT * FROM cartodb.CDB_Organization_Add_Table_Read_Write_Permission('cdb_testmember_1', 'foo', 'cdb_testmember_2')"
    sql cdb_testmember_2 'INSERT INTO cdb_testmember_1.foo VALUES (5), (6), (7), (8), (9);'
    sql cdb_testmember_1 'SELECT count(*) FROM cdb_testmember_1.foo;' should 5
    sql cdb_testmember_2 'SELECT count(*) FROM cdb_testmember_1.foo;' should 5
    sql cdb_testmember_2 'DELETE FROM cdb_testmember_1.foo where a = 9;'
    sql cdb_testmember_1 'SELECT count(*) FROM cdb_testmember_1.foo;' should 4
    sql cdb_testmember_2 'SELECT count(*) FROM cdb_testmember_1.foo;' should 4

    sql cdb_testmember_1 "ALTER TABLE cdb_testmember_1.foo DROP cartodb_id;"

    # Cleanup
    truncate_table cdb_testmember_1 foo
    sql cdb_testmember_1 "SELECT * FROM cartodb.CDB_Organization_Remove_Access_Permission('cdb_testmember_1', 'foo', 'cdb_testmember_2')"
}

function test_member_1_removes_access_and_member_2_can_no_longer_query_the_table() {
    sql cdb_testmember_1 'INSERT INTO cdb_testmember_1.foo VALUES (5), (6), (7), (8), (9), (10);'
    sql cdb_testmember_1 "SELECT * FROM cartodb.CDB_Organization_Add_Table_Read_Permission('cdb_testmember_1', 'foo', 'cdb_testmember_2')"
    sql cdb_testmember_2 'SELECT count(*) FROM cdb_testmember_1.foo;' should 6
    sql cdb_testmember_1 "SELECT * FROM cartodb.CDB_Organization_Remove_Access_Permission('cdb_testmember_1', 'foo', 'cdb_testmember_2')"
    sql cdb_testmember_2 'SELECT * FROM cdb_testmember_1.foo;' fails

    # Cleanup
    truncate_table cdb_testmember_1 foo
}

function test_member_1_removes_access_and_member_2_can_no_longer_write_to_the_table() {
    sql cdb_testmember_1 "SELECT * FROM cartodb.CDB_Organization_Add_Table_Read_Write_Permission('cdb_testmember_1', 'foo', 'cdb_testmember_2')"
    sql cdb_testmember_2 'INSERT INTO cdb_testmember_1.foo VALUES (5), (6), (7), (8), (9);'
    sql cdb_testmember_1 "SELECT * FROM cartodb.CDB_Organization_Remove_Access_Permission('cdb_testmember_1', 'foo', 'cdb_testmember_2')"
    sql cdb_testmember_2 'INSERT INTO cdb_testmember_1.foo VALUES (5), (6), (7), (8), (9);' fails

    # Cleanup
    truncate_table cdb_testmember_1 foo
}

function test_giving_permissions_to_two_tables_and_removing_from_first_table_should_not_remove_from_second() {
    #### test setup
    # create an extra table for cdb_testmember_1
    create_table cdb_testmember_1 foo_2
    sql cdb_testmember_1 'INSERT INTO cdb_testmember_1.foo VALUES (1), (2), (3), (4);'
    sql cdb_testmember_1 'INSERT INTO cdb_testmember_1.foo_2 VALUES (1), (2), (3), (4), (5);'
    sql cdb_testmember_1 'SELECT * FROM cdb_testmember_1.foo_2;'

    # gives read permission to both tables
    sql cdb_testmember_1 "SELECT * FROM cartodb.CDB_Organization_Add_Table_Read_Permission('cdb_testmember_1', 'foo', 'cdb_testmember_2')"
    sql cdb_testmember_1 "SELECT * FROM cartodb.CDB_Organization_Add_Table_Read_Permission('cdb_testmember_1', 'foo_2', 'cdb_testmember_2')"

    # cdb_testmember_2 has access to both tables
    sql cdb_testmember_2 'SELECT count(*) FROM cdb_testmember_1.foo;' should 4
    sql cdb_testmember_2 'SELECT count(*) FROM cdb_testmember_1.foo_2;' should 5

    # cdb_testmember_1 removes access to foo table
    sql cdb_testmember_1 "SELECT * FROM cartodb.CDB_Organization_Remove_Access_Permission('cdb_testmember_1', 'foo', 'cdb_testmember_2')"

    # cdb_testmember_2 should have access to foo_2 table but not to table foo
    sql cdb_testmember_2 'SELECT count(*) FROM cdb_testmember_1.foo;' fails
    sql cdb_testmember_2 'SELECT count(*) FROM cdb_testmember_1.foo_2;' should 5


    #### test tear down
    truncate_table cdb_testmember_1 foo
    sql cdb_testmember_1 'DROP TABLE cdb_testmember_1.foo_2;'
}

function test_cdb_org_member_role_allows_reading_to_all_users_without_explicit_permission() {
    sql cdb_testmember_1 'INSERT INTO cdb_testmember_1.foo VALUES (1), (2), (3), (4);'

    sql cdb_testmember_2 'SELECT count(*) FROM cdb_testmember_1.foo;' fails
    sql cdb_testmember_1 "SELECT cartodb.CDB_Organization_Add_Table_Organization_Read_Permission('cdb_testmember_1', 'foo');"
    sql cdb_testmember_2 'SELECT count(*) FROM cdb_testmember_1.foo;' should 4

    # Cleanup
    sql cdb_testmember_1 "SELECT cartodb.CDB_Organization_Remove_Organization_Access_Permission('cdb_testmember_1', 'foo');"
    truncate_table cdb_testmember_1 foo
}

function test_user_can_read_when_it_has_permission_after_organization_permission_is_removed() {
    create_role_and_schema cdb_testmember_3
    sql cdb_testmember_1 'INSERT INTO cdb_testmember_1.foo VALUES (1), (2), (3), (4);'

    # shares with cdb_testmember_2 and can read but cdb_testmember_3 cannot
    sql cdb_testmember_1 "SELECT * FROM cartodb.CDB_Organization_Add_Table_Read_Permission('cdb_testmember_1', 'foo', 'cdb_testmember_2')"
    sql cdb_testmember_2 'SELECT count(*) FROM cdb_testmember_1.foo;' should 4
    sql cdb_testmember_3 'SELECT count(*) FROM cdb_testmember_1.foo;' fails

    # granting to organization allows to read to both: cdb_testmember_2 and cdb_testmember_3
    sql cdb_testmember_1 "SELECT cartodb.CDB_Organization_Add_Table_Organization_Read_Permission('cdb_testmember_1', 'foo');"
    sql cdb_testmember_2 'SELECT count(*) FROM cdb_testmember_1.foo;' should 4
    sql cdb_testmember_3 'SELECT count(*) FROM cdb_testmember_1.foo;' should 4

    # removing access from organization should keep permission on cdb_testmember_2 but drop it to cdb_testmember_3
    sql cdb_testmember_1 "SELECT cartodb.CDB_Organization_Remove_Organization_Access_Permission('cdb_testmember_1', 'foo');"
    sql cdb_testmember_2 'SELECT count(*) FROM cdb_testmember_1.foo;' should 4
    sql cdb_testmember_3 'SELECT count(*) FROM cdb_testmember_1.foo;' fails

    # Cleanup
    sql cdb_testmember_1 "SELECT * FROM cartodb.CDB_Organization_Remove_Access_Permission('cdb_testmember_1', 'foo', 'cdb_testmember_2')"
    truncate_table cdb_testmember_1 foo
    drop_role_and_schema cdb_testmember_3
}

function test_cdb_querytables_returns_schema_and_table_name() {
    sql cdb_testmember_1 "select * from CDB_QueryTables('select * from foo');" should "{cdb_testmember_1.foo}"
}

function test_cdb_querytables_works_with_parentheses() {
    sql cdb_testmember_1 "select * from CDB_QueryTables('(select * from foo)');" should "{cdb_testmember_1.foo}"
}

function test_cdb_querytables_returns_schema_and_table_name_for_several_schemas() {
    sql postgres "select * from CDB_QueryTables('select * from cdb_testmember_1.foo, cdb_testmember_2.bar');" should "{cdb_testmember_1.foo,cdb_testmember_2.bar}"
}

function test_cdb_querytables_does_not_return_functions_as_part_of_the_resultset() {
    sql postgres "select * from CDB_QueryTables('select * from cdb_testmember_1.foo, cdb_testmember_2.bar, plainto_tsquery(''foo'')');" should "{cdb_testmember_1.foo,cdb_testmember_2.bar}"
}

function test_cdb_usertables_should_work_with_orgusers() {

    # This test validates the changes proposed in https://github.com/CartoDB/cartodb/pull/5021

    # create tables
    sql cdb_testmember_1 "CREATE TABLE test_perms_pub (a int)"
    sql cdb_testmember_1 "INSERT INTO test_perms_pub (a) values (1);"
    sql cdb_testmember_1 "GRANT SELECT ON TABLE test_perms_pub TO publicuser"

    sql cdb_testmember_1 "CREATE TABLE test_perms_priv (a int)"


    # this is what we need to make public tables available in CDB_UserTables
    sql postgres "grant publicuser to cdb_testmember_1;"
    sql postgres "grant publicuser to cdb_testmember_2;"


    # this is required to enable select from other schema
    sql postgres "GRANT USAGE ON SCHEMA cdb_testmember_1 TO publicuser";

    sql publicuser "SELECT count(*) FROM CDB_UserTables('all')" should 1
    sql publicuser "SELECT count(*) FROM CDB_UserTables('public')" should 1
    sql publicuser "SELECT count(*) FROM CDB_UserTables('private')" should 0
    sql publicuser "SELECT * FROM CDB_UserTables('all')" should "test_perms_pub"
    sql publicuser "SELECT * FROM CDB_UserTables('public')" should "test_perms_pub"
    sql publicuser "SELECT * FROM CDB_UserTables('private')" should ""
    # the following tests are for https://github.com/CartoDB/cartodb-postgresql/issues/98
    # cdb_testmember_2 is already owner of `bar` table
    sql cdb_testmember_2 "select string_agg(t,',') from (select cdb_usertables('all') t order by t) as s" should "bar,test_perms_pub"
    sql cdb_testmember_2 "SELECT * FROM CDB_UserTables('public')" should "test_perms_pub"
    sql cdb_testmember_2 "SELECT * FROM CDB_UserTables('private')" should "bar"

    # test cdb_testmember_2 can select from cdb_testmember_1's public table
    sql cdb_testmember_2 "SELECT * FROM cdb_testmember_1.test_perms_pub" should 1

    sql postgres 'REVOKE USAGE ON SCHEMA cdb_testmember_1 FROM publicuser;'
    sql cdb_testmember_1 "DROP TABLE test_perms_pub"
    sql cdb_testmember_1 "DROP TABLE test_perms_priv"
}

function test_CDB_Group_Table_GrantRead_should_grant_select_and_RevokeAll_should_remove_it() {
    create_table cdb_testmember_2 shared_with_group

    sql cdb_testmember_1 'SELECT count(*) FROM cdb_testmember_2.shared_with_group;' fails
    sql cdb_testmember_2 'SELECT count(*) FROM cdb_testmember_2.shared_with_group;'
    sql cdb_testmember_2 "select cartoDB.CDB_Group_Table_GrantRead('group_a', 'cdb_testmember_2', 'shared_with_group')"
    sql cdb_testmember_1 'SELECT count(*) FROM cdb_testmember_2.shared_with_group;'
    sql cdb_testmember_2 'SELECT count(*) FROM cdb_testmember_2.shared_with_group;'
    sql cdb_testmember_2 "select cartoDB.CDB_Group_Table_RevokeAll('group_a', 'cdb_testmember_2', 'shared_with_group')"
    sql cdb_testmember_1 'SELECT count(*) FROM cdb_testmember_2.shared_with_group;' fails
    sql cdb_testmember_2 'SELECT count(*) FROM cdb_testmember_2.shared_with_group;'

    sql cdb_testmember_2 'DROP TABLE cdb_testmember_2.shared_with_group;'
}

function test_CDB_Group_Table_GrantReadWrite_should_grant_insert_and_RevokeAll_should_remove_it() {
    create_table cdb_testmember_2 shared_with_group

    sql cdb_testmember_1 'INSERT INTO cdb_testmember_2.shared_with_group VALUES (1), (2), (3), (4), (5)' fails
    sql cdb_testmember_2 'INSERT INTO cdb_testmember_2.shared_with_group VALUES (1), (2), (3), (4), (5)'
    sql cdb_testmember_2 "select cartoDB.CDB_Group_Table_GrantReadWrite('group_a', 'cdb_testmember_2', 'shared_with_group')"
    sql cdb_testmember_1 'INSERT INTO cdb_testmember_2.shared_with_group VALUES (1), (2), (3), (4), (5)'
    sql cdb_testmember_2 'INSERT INTO cdb_testmember_2.shared_with_group VALUES (1), (2), (3), (4), (5)'
    sql cdb_testmember_2 "select cartoDB.CDB_Group_Table_RevokeAll('group_a', 'cdb_testmember_2', 'shared_with_group')"
    sql cdb_testmember_1 'INSERT INTO cdb_testmember_2.shared_with_group VALUES (1), (2), (3), (4), (5)' fails
    sql cdb_testmember_2 'INSERT INTO cdb_testmember_2.shared_with_group VALUES (1), (2), (3), (4), (5)'

    sql cdb_testmember_2 'DROP TABLE cdb_testmember_2.shared_with_group;'
}

function test_group_management_functions_cant_be_used_by_normal_members() {
    sql cdb_testmember_1 "SELECT cartodb.CDB_Group_CreateGroup('group_x_1');" fails
    sql cdb_testmember_1 "SELECT cartodb.CDB_Group_RenameGroup('group_a', 'group_x_2');" fails
    sql cdb_testmember_1 "SELECT cartodb.CDB_Group_DropGroup('group_a');" fails
    sql cdb_testmember_1 "SELECT cartodb.CDB_Group_AddUsers('group_a', ARRAY['cdb_testmember_2']);" fails
    sql cdb_testmember_1 "SELECT cartodb.CDB_Group_RemoveUsers('group_a', ARRAY['cdb_testmember_1']);" fails
}

function test_group_permission_functions_cant_be_used_by_normal_members() {
    create_table cdb_testmember_2 shared_with_group

    sql cdb_testmember_1 "select cartoDB.CDB_Group_Table_GrantRead('group_a', 'cdb_testmember_2', 'shared_with_group');" fails
    sql cdb_testmember_1 "select cartoDB.CDB_Group_Table_GrantReadWrite('group_a', 'cdb_testmember_2', 'shared_with_group');" fails

    # Checks that you can't grant even if your group has RW permissions
    sql cdb_testmember_2 "select cartoDB.CDB_Group_Table_GrantReadWrite('group_a', 'cdb_testmember_2', 'shared_with_group')"
    sql cdb_testmember_1 "select cartoDB.CDB_Group_Table_GrantRead('group_a', 'cdb_testmember_2', 'shared_with_group');" fails
    sql cdb_testmember_1 "select cartoDB.CDB_Group_Table_GrantReadWrite('group_b', 'cdb_testmember_2', 'shared_with_group');" fails
    sql cdb_testmember_1 "select cartoDB.CDB_Group_Table_RevokeAll('group_b', 'cdb_testmember_2', 'shared_with_group');" fails

    sql cdb_testmember_2 'DROP TABLE cdb_testmember_2.shared_with_group;'
}

function test_group_management_functions_can_be_used_by_org_admin() {
    sql cdb_org_admin "SELECT cartodb.CDB_Group_CreateGroup('group_x_tmp');"
    sql cdb_org_admin "SELECT cartodb.CDB_Group_RenameGroup('group_x_tmp', 'group_x');"
    sql cdb_org_admin "SELECT cartodb.CDB_Group_AddUsers('group_x', ARRAY['cdb_testmember_1', 'cdb_testmember_2']);"
    sql cdb_org_admin "SELECT cartodb.CDB_Group_RemoveUsers('group_x', ARRAY['cdb_testmember_1', 'cdb_testmember_2']);"
    # TODO: workaround superadmin limitation
    sql "SELECT cartodb.CDB_Group_DropGroup('group_x');"
}

function test_org_admin_cant_grant_permissions_on_tables_he_does_not_own() {
    create_table cdb_testmember_2 shared_with_group

    sql cdb_org_admin "select cartoDB.CDB_Group_Table_GrantRead('group_a', 'cdb_testmember_2', 'shared_with_group');" fails
    sql cdb_org_admin "select cartoDB.CDB_Group_Table_GrantReadWrite('group_a', 'cdb_testmember_2', 'shared_with_group');" fails

    # Checks that you can't grant even if your group has RW permissions
    sql cdb_testmember_2 "select cartoDB.CDB_Group_Table_GrantReadWrite('group_a', 'cdb_testmember_2', 'shared_with_group')"
    sql cdb_org_admin "select cartoDB.CDB_Group_Table_GrantRead('group_a', 'cdb_testmember_2', 'shared_with_group');" fails
    sql cdb_org_admin "select cartoDB.CDB_Group_Table_GrantReadWrite('group_b', 'cdb_testmember_2', 'shared_with_group');" fails
    sql cdb_org_admin "select cartoDB.CDB_Group_Table_RevokeAll('group_b', 'cdb_testmember_2', 'shared_with_group');" fails

    sql cdb_testmember_2 'DROP TABLE cdb_testmember_2.shared_with_group;'
}

function test_valid_group_names() {
    sql postgres "select cartodb._CDB_Group_GroupRole('group_1$_a');"
    sql postgres "select cartodb._CDB_Group_GroupRole('GROUP_1$_A');"
    sql postgres "select cartodb._CDB_Group_GroupRole('_group_1$_a');"
}

function test_administrator_name_generation() {
    sql postgres "select cartodb._CDB_Organization_Admin_Role_Name();"
}

function test_conf() {
    sql postgres "SELECT cartodb.CDB_Conf_GetConf('test_conf')" should ''
    sql postgres "SELECT cartodb.CDB_Conf_GetConf('test_conf_2')" should ''

    sql postgres "SELECT cartodb.CDB_Conf_SetConf('test_conf', '{ \"a_key\": \"test_val\" }')"

    sql postgres "SELECT cartodb.CDB_Conf_GetConf('test_conf')" should '{ "a_key": "test_val" }'
    sql postgres "SELECT cartodb.CDB_Conf_GetConf('test_conf_2')" should ''

    sql postgres "SELECT cartodb.CDB_Conf_RemoveConf('test_conf')"

    sql postgres "SELECT cartodb.CDB_Conf_GetConf('test_conf')" should ''
    sql postgres "SELECT cartodb.CDB_Conf_GetConf('test_conf_2')" should ''
}

#################################################### TESTS END HERE ####################################################



run_tests $@

exit ${OK}
