# cartodb/Makefile

EXTENSION = cartodb
EXTVERSION = 0.1dev

CDBSCRIPTS = \
  scripts-available/CDB_Roles.sql \
  scripts-enabled/*.sql \
  $(END)

DATA_built = \
  $(EXTENSION)--$(EXTVERSION).sql \
  $(EXTENSION)--unpackaged--$(EXTVERSION).sql \
  $(EXTENSION).control \
  cartodb_version.sql

DOCS = README.md
REGRESS_NEW = test_ddl_triggers
REGRESS_OLD = $(wildcard test/*.sql)
REGRESS_LEGACY = $(REGRESS_OLD:.sql=)
REGRESS = test_setup $(REGRESS_NEW) $(REGRESS_LEGACY)

PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

$(EXTENSION)--$(EXTVERSION).sql: $(CDBSCRIPTS) cartodb_hooks.sql cartodb_version.sql Makefile 
	echo '\echo Use "CREATE EXTENSION cartodb" to load this file. \quit' > $@
	cat $(CDBSCRIPTS) | \
    sed -e 's/\<public\./cartodb./g' \
        -e 's/:DATABASE_USERNAME/cdb_org_admin/g' >> $@
	echo "GRANT USAGE ON SCHEMA cartodb TO public;" >> $@
	cat cartodb_hooks.sql >> $@
	cat cartodb_version.sql >> $@

$(EXTENSION)--unpackaged--$(EXTVERSION).sql: $(EXTENSION)--$(EXTVERSION).sql util/create_from_unpackaged.sh Makefile
	./util/create_from_unpackaged.sh $(EXTVERSION)

$(EXTENSION).control: $(EXTENSION).control.in
	sed -e 's/@@VERSION@@/$(EXTVERSION)/' $< > $@

cartodb_version.sql: cartodb_version.sql.in
	sed -e 's/@@VERSION@@/$(EXTVERSION)/' $< > $@

legacy_regress: $(REGRESS_OLD) Makefile
	mkdir -p sql/test/
	mkdir -p expected/test/
	mkdir -p results/test/
	for f in $(REGRESS_OLD); do \
    tn=`basename $${f} .sql`; \
    of=sql/test/$${tn}.sql; \
    echo '\\set ECHO off' > $${of}; \
    echo '\\a' >> $${of}; \
    echo '\\t' >> $${of}; \
    echo '\\set QUIET off' >> $${of}; \
    cat $${f} | \
      sed -e 's/\<public\./cartodb./g' >> $${of}; \
    exp=expected/test/$${tn}.out; \
    echo '\\set ECHO off' > $${exp}; \
    cat test/$${tn}_expect >> $${exp}; \
  done

legacy_tests: legacy_regress 

installcheck: legacy_tests

