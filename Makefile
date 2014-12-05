# cartodb/Makefile

EXTENSION = cartodb
EXTVERSION = 0.5.1

SED = sed

CDBSCRIPTS = \
  scripts-enabled/*.sql \
  scripts-available/CDB_SearchPath.sql \
  scripts-available/CDB_DDLTriggers.sql \
  scripts-available/CDB_ExtensionPost.sql \
  scripts-available/CDB_ExtensionUtils.sql \
  $(END)

UPGRADABLE = \
  unpackaged \
  0.1.0 \
  0.1.1 \
  0.2.0 \
  0.2.1 \
  0.3.0 \
  0.3.0dev \
  0.3.1 \
  0.3.2 \
  0.3.3 \
  0.3.4 \
  0.3.5 \
  0.3.6 \
  0.4.0 \
  0.4.1 \
  0.5.0 \
  $(EXTVERSION)dev \
  $(EXTVERSION)next \
  $(END)

UPGRADES = \
  $(shell echo $(UPGRADABLE) | \
     $(SED) 's/^/$(EXTENSION)--/' | \
     $(SED) 's/$$/--$(EXTVERSION).sql/' | \
     $(SED) 's/ /--$(EXTVERSION).sql $(EXTENSION)--/g')

GITDIR=$(shell test -d .git && echo '.git' || cat .git | $(SED) 's/^gitdir: //')

DATA_built = \
  $(EXTENSION)--$(EXTVERSION).sql \
  $(EXTENSION)--$(EXTVERSION)--$(EXTVERSION)next.sql \
  $(UPGRADES) \
  $(EXTENSION).control

EXTRA_CLEAN = cartodb_version.sql

DOCS = README.md
REGRESS_NEW = test_ddl_triggers
REGRESS_OLD = $(wildcard test/*.sql)
REGRESS_LEGACY = $(REGRESS_OLD:.sql=)
REGRESS = test_setup $(REGRESS_NEW) $(REGRESS_LEGACY)

PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

$(EXTENSION)--$(EXTVERSION).sql: $(CDBSCRIPTS) cartodb_version.sql Makefile 
	echo '\echo Use "CREATE EXTENSION $(EXTENSION)" to load this file. \quit' > $@
	cat $(CDBSCRIPTS) | \
    $(SED) -e 's/public\./cartodb./g' \
        -e 's/:DATABASE_USERNAME/cdb_org_admin/g' >> $@
	echo "GRANT USAGE ON SCHEMA cartodb TO public;" >> $@
	cat cartodb_version.sql >> $@

$(EXTENSION)--unpackaged--$(EXTVERSION).sql: $(EXTENSION)--$(EXTVERSION).sql util/create_from_unpackaged.sh Makefile
	./util/create_from_unpackaged.sh $(EXTVERSION)

$(EXTENSION)--%--$(EXTVERSION).sql: $(EXTENSION)--$(EXTVERSION).sql
	cp $< $@

$(EXTENSION)--$(EXTVERSION)--$(EXTVERSION)next.sql: $(EXTENSION)--$(EXTVERSION).sql
	cp $< $@

$(EXTENSION).control: $(EXTENSION).control.in Makefile
	$(SED) -e 's/@@VERSION@@/$(EXTVERSION)/' $< > $@

cartodb_version.sql: cartodb_version.sql.in Makefile $(GITDIR)/index
	$(SED) -e 's/@@VERSION@@/$(EXTVERSION)/' $< > $@

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
      $(SED) -e 's/public\./cartodb./g' >> $${of}; \
    exp=expected/test/$${tn}.out; \
    echo '\\set ECHO off' > $${exp}; \
    cat test/$${tn}_expect >> $${exp}; \
  done

test_organization:
	bash test/organization/test.sh

test_extension_new:
	bash test/extension/test.sh

legacy_tests: legacy_regress 

installcheck: legacy_tests test_extension_new test_organization

