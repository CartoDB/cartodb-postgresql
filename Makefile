# cartodb/Makefile

EXTENSION = cartodb
EXTVERSION = 0.1

CDBSCRIPTS = \
  scripts-available/CDB_TableMetadata.sql \
  scripts-available/CDB_Quota.sql \
  scripts-available/CDB_TransformToWebmercator.sql \
  scripts-available/CDB_CartodbfyTable.sql \
  $(END)

DATA_built = $(EXTENSION)--$(EXTVERSION).sql 
DOCS = README.md
REGRESS = test_ddl_triggers

PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

$(EXTENSION)--$(EXTVERSION).sql: $(CDBSCRIPTS) cartodb_hooks.sql Makefile 
	cat $(CDBSCRIPTS) | sed 's/\<public\./cartodb./g' > $@
	echo "GRANT USAGE ON SCHEMA cartodb TO public;" >> $@
	cat cartodb_hooks.sql >> $@
