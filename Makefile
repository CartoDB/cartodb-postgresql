# cartodb/Makefile

EXTENSION = cartodb
EXTVERSION = 0.1

CDBSCRIPTS = \
  scripts-enabled/*.sql \
  $(END)

DATA_built = $(EXTENSION)--$(EXTVERSION).sql 
DOCS = README.md
REGRESS = test_ddl_triggers

PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

$(EXTENSION)--$(EXTVERSION).sql: $(CDBSCRIPTS) cartodb_hooks.sql Makefile 
	echo "SET search_path TO cartodb,public,pg_catalog;" > $@
	cat $(CDBSCRIPTS) | \
    sed -e 's/\<public\./cartodb./g' \
        -e 's/:DATABASE_USERNAME/cdb_org_admin/g' >> $@
	echo "GRANT USAGE ON SCHEMA cartodb TO public;" >> $@
	cat cartodb_hooks.sql >> $@
