# cartodb/Makefile

EXTENSION = cartodb
EXTVERSION = 0.1

DATA_built = $(EXTENSION)--$(EXTVERSION).sql 
#DOCS = README.md
#REGRESS = hook_on_table_create

PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

$(EXTENSION)--$(EXTVERSION).sql: cartodb_hooks.sql
	cat $< | grep -v '^\(BEGIN\|END\);$$' > $@
