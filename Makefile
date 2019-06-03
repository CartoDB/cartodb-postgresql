# cartodb/Makefile

EXTENSION = cartodb
EXTVERSION = 0.26.1

SED = sed
AWK = awk

CDBSCRIPTS = \
  scripts-enabled/*.sql \
  scripts-available/CDB_SearchPath.sql \
  scripts-available/CDB_ExtensionPost.sql \
  scripts-available/CDB_ExtensionUtils.sql \
  scripts-available/CDB_Helper.sql \
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
  0.5.1 \
  0.5.2 \
  0.5.3 \
  0.6.0 \
  0.7.0 \
  0.7.1 \
  0.7.2 \
  0.7.3 \
  0.7.4 \
  0.8.0 \
  0.8.1 \
  0.8.2 \
  0.9.0 \
  0.9.1 \
  0.9.2 \
  0.9.3 \
  0.9.4 \
  0.10.0 \
  0.10.1 \
  0.10.2 \
  0.11.0 \
  0.11.1 \
  0.11.2 \
  0.11.3 \
  0.11.4 \
  0.11.5 \
  0.12.0 \
  0.13.0 \
  0.13.1 \
  0.14.0 \
  0.14.1 \
  0.14.2 \
  0.14.3 \
  0.14.4 \
  0.15.0 \
  0.15.1 \
  0.16.0 \
  0.16.1 \
  0.16.2 \
  0.16.3 \
  0.16.4 \
  0.17.0 \
  0.17.1 \
  0.18.0 \
  0.18.1 \
  0.18.2 \
  0.18.3 \
  0.18.4 \
  0.18.5 \
  0.19.0 \
  0.19.1 \
  0.19.2 \
  0.20.0 \
  0.21.0 \
  0.22.0 \
  0.22.1 \
  0.22.2 \
  0.23.0 \
  0.23.1 \
  0.23.2 \
  0.24.0 \
  0.24.1 \
  0.25.0 \
  0.26.0 \
  0.26.1 \
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
REGRESS_OLD = $(wildcard test/*.sql)
REGRESS_LEGACY = $(REGRESS_OLD:.sql=)
REGRESS = test_setup $(REGRESS_LEGACY)

PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

$(EXTENSION)--$(EXTVERSION).sql: $(CDBSCRIPTS) cartodb_version.sql Makefile
	echo '\echo Use "CREATE EXTENSION $(EXTENSION)" to load this file. \quit' > $@
	cat $(CDBSCRIPTS) | \
	$(SED) 	-e 's/@extschema@/cartodb/g' \
		-e "s/@postgisschema@/public/g" >> $@
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
	$(SED) -e 's/@@VERSION@@/$(EXTVERSION)/' -e 's/@extschema@/cartodb/g' -e "s/@postgisschema@/public/g" $< > $@

# Needed for consistent `echo` results with backslashes
SHELL = bash

legacy_regress: $(REGRESS_OLD) Makefile
	mkdir -p sql/test/
	mkdir -p expected/test/
	mkdir -p results/test/
	for f in $(REGRESS_OLD); do \
		tn=`basename $${f} .sql`; \
		of=sql/test/$${tn}.sql; \
		echo '\set ECHO none' > $${of}; \
		echo '\a' >> $${of}; \
		echo '\t' >> $${of}; \
		echo '\set QUIET off' >> $${of}; \
		cat $${f} | \
			$(SED) -e 's/@@VERSION@@/$(EXTVERSION)/' -e 's/@extschema@/cartodb/g' -e "s/@postgisschema@/public/g" >> $${of}; \
		exp=expected/test/$${tn}.out; \
		echo '\set ECHO none' > $${exp}; \
		cat test/$${tn}_expect >> $${exp}; \
	done

test_organization:
	bash test/organization/test.sh

test_extension_new:
	bash test/extension/test.sh

legacy_tests: legacy_regress

installcheck: legacy_tests test_extension_new test_organization

