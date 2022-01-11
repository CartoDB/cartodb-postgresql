#!/usr/bin/env sh

set_failed() {
    OK=1
    PARTIALOK=1
}


clear_partial_result() {
    PARTIALOK=0
}

log_info()
{
    printf "\n\n\n"
    _log "1;34m" "$1"
}

log_error() {
    _log "1;31m" "$1"
}

log_debug() {
    _log "1;32m" "> $1"
}

log_warning() {
    _log "0;33m" "$1"
}

_log() {
    printf "\033[$1%s\033[0m\n" "$2"
}


create_role_and_schema() {
    create_role_and_schema_ROLE="$1"
    sql "CREATE ROLE ${create_role_and_schema_ROLE} LOGIN;"
    sql "GRANT CONNECT ON DATABASE \"${DATABASE}\" TO ${create_role_and_schema_ROLE};"
    sql "CREATE SCHEMA ${create_role_and_schema_ROLE} AUTHORIZATION ${create_role_and_schema_ROLE};"
    sql "GRANT USAGE ON SCHEMA cartodb TO ${create_role_and_schema_ROLE};"
    sql "SELECT cartodb.CDB_Organization_Create_Member('${create_role_and_schema_ROLE}');"
    sql "ALTER ROLE ${create_role_and_schema_ROLE} SET search_path TO ${create_role_and_schema_ROLE},cartodb,public;"
    unset create_role_and_schema_ROLE
}


drop_role_and_schema() {
    drop_role_and_schema_ROLE="$1"
    sql "REVOKE USAGE ON SCHEMA cartodb FROM ${drop_role_and_schema_ROLE};"
    sql "DROP SCHEMA \"${drop_role_and_schema_ROLE}\" CASCADE;"
    sql "REVOKE CONNECT ON DATABASE \"${DATABASE}\" FROM \"${drop_role_and_schema_ROLE}\";"
    sql "DROP ROLE \"${drop_role_and_schema_ROLE}\";"
    unset drop_role_and_schema_ROLE
}


create_table() {
    if [ $# -ne 2 ]
    then
        log_error "create_table requires two arguments: role and table_name"
        exit 1
    fi

    create_table_ROLE="$1"
    create_table_TABLENAME="$2"

    sql "${create_table_ROLE}" "CREATE TABLE ${create_table_ROLE}.${create_table_TABLENAME} ( a int );"

    unset create_table_ROLE
    unset create_table_TABLENAME
}


create_raster_table() {
    if [ $# -ne 2 ]
    then
        log_error "create_raster_table requires two arguments: role and table_name"
        exit 1
    fi

    create_raster_table_RASTER_COL="the_raster_webmercator"
    create_raster_table_ROLE="$1"
    create_raster_table_TABLENAME="$2"
    create_raster_table_OVERVIEW_TABLENAME="o_2_${create_raster_table_TABLENAME}"

    sql "${create_raster_table_ROLE}" "CREATE TABLE ${create_raster_table_ROLE}.${create_raster_table_TABLENAME} (rid serial PRIMARY KEY, ${create_raster_table_RASTER_COL} raster);"

    sql "${create_raster_table_ROLE}" "CREATE TABLE ${create_raster_table_ROLE}.${create_raster_table_OVERVIEW_TABLENAME} (rid serial PRIMARY KEY, ${create_raster_table_RASTER_COL} raster);"

    sql "${create_raster_table_ROLE}" "SELECT AddOverviewConstraints('${create_raster_table_ROLE}','${create_raster_table_OVERVIEW_TABLENAME}','${create_raster_table_RASTER_COL}','${create_raster_table_ROLE}','${create_raster_table_TABLENAME}','${create_raster_table_RASTER_COL}',2);"

    unset create_raster_table_RASTER_COL
    unset create_raster_table_ROLE
    unset create_raster_table_TABLENAME
    unset create_raster_table_OVERVIEW_TABLENAME
}

drop_raster_table() {
    if [ $# -ne 2 ]
    then
        log_error "drop_raster_table requires two arguments: role and table_name"
        exit 1
    fi

    drop_raster_table_ROLE="$1"
    drop_raster_table_TABLENAME="$2"
    drop_raster_table_OVERVIEW_TABLENAME="o_2_${drop_raster_table_TABLENAME}"

    sql "${drop_raster_table_ROLE}" "DROP TABLE ${drop_raster_table_ROLE}.${drop_raster_table_OVERVIEW_TABLENAME};"
    sql "${drop_raster_table_ROLE}" "DROP TABLE ${drop_raster_table_ROLE}.${drop_raster_table_TABLENAME};"

    unset drop_raster_table_ROLE
    unset drop_raster_table_TABLENAME
    unset drop_raster_table_OVERVIEW_TABLENAME
}

truncate_table() {
    if [ $# -ne 2 ]
    then
        log_error "truncate_table requires two arguments: role and table_name"
        exit 1
    fi
    truncate_table_ROLE="$1"
    truncate_table_TABLENAME="$2"
    sql ${truncate_table_ROLE} "TRUNCATE TABLE ${truncate_table_ROLE}.${truncate_table_TABLENAME};"
    unset truncate_table_ROLE
    unset truncate_table_TABLENAME
}

run_tests() {
    run_tests_FAILED_TESTS=""
    if [ $# -ge 1 ]
    then
        if [ $# -eq 1 ]
        then
            run_tests_TESTS=$(< "$0" grep -o "$1[^\(]*")
        else
            run_tests_TESTS=$@
        fi
    else
        run_tests_TESTS=$(< "$0" perl -n -e'/^(test.*)\(\)/ && print "$1\n"')
    fi
    setup
    for t in ${run_tests_TESTS}
    do
        printf "####################################################################\n"
        printf "#\n"
        printf "# Running: %s\n" "${t}"
        printf "#\n"
        printf "####################################################################\n"

        clear_partial_result
        eval "${t}"
        if [ ${PARTIALOK} -ne 0 ]
        then
            run_tests_FAILED_TESTS="${run_tests_FAILED_TESTS}\n\t${t}"
        fi
    done
    tear_down
    if [ ${OK} -ne 0 ]
    then
        printf "\n"
        log_error "The following tests are failing:"
        printf '%s\n' "$(printf "${run_tests_FAILED_TESTS}" | tail +2)"
    fi

    unset run_tests_FAILED_TESTS
    unset run_tests_TESTS
}
