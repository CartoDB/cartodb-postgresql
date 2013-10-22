LOAD 'schema_triggers.so';
CREATE EXTENSION IF NOT EXISTS schema_triggers;

GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA schema_triggers TO public;

BEGIN;

-- Table creation
-- {
CREATE OR REPLACE FUNCTION cdb_handle_create_table ()
RETURNS event_trigger SECURITY DEFINER LANGUAGE plpgsql AS $$
DECLARE
  event_info RECORD;
BEGIN
  event_info := schema_triggers.get_relation_create_eventinfo();

  -- We're only interested in real relations
  IF (event_info.new).relkind != 'r' THEN RETURN; END IF;

  RAISE DEBUG 'Relation % of kind % created in namespace oid %',
	 event_info.relation, (event_info.new).relkind, (event_info.new).relnamespace;

  -- We don't want to react to alters triggered by superuser,
  IF current_setting('is_superuser') = 'on' THEN
    RAISE DEBUG 'no ddl trigger for superuser';
    RETURN;
  END IF;

  -- CDB_CartodbfyTable must not create tables, or infinite loop will happen
  PERFORM public.CDB_CartodbfyTable(event_info.relation);

END; $$;
-- }

-- Column alter
-- {
CREATE OR REPLACE FUNCTION cdb_handle_alter_column ()
RETURNS event_trigger SECURITY DEFINER LANGUAGE plpgsql AS $$
DECLARE
  event_info RECORD;
  rel RECORD;
BEGIN
  event_info := schema_triggers.get_column_alter_eventinfo();

  SELECT oid,* FROM pg_class WHERE oid = event_info.relation INTO rel;

  RAISE DEBUG 'Column % altered by % (superuser? %) in relation % of kind %',
	 (event_info.old).attname, current_user, current_setting('is_superuser'), event_info.relation::regclass, rel.relkind;

  -- We're only interested in real relations
  IF rel.relkind != 'r' THEN RETURN; END IF;

  -- We don't want to react to alters triggered by superuser,
  IF current_setting('is_superuser') = 'on' THEN
    RAISE DEBUG 'no ddl trigger for superuser';
    RETURN;
  END IF;

  PERFORM cdb_disable_ddl_hooks();

  PERFORM public.CDB_CartodbfyTable(event_info.relation);

  PERFORM cdb_enable_ddl_hooks();

  -- TODO: invalidate varnish 

END; $$;
-- }

-- Column drop
-- {
CREATE OR REPLACE FUNCTION cdb_handle_drop_column ()
RETURNS event_trigger SECURITY DEFINER LANGUAGE plpgsql AS $$
DECLARE
  event_info RECORD;
  rel RECORD;
BEGIN
  event_info := schema_triggers.get_column_drop_eventinfo();

  SELECT oid,* FROM pg_class WHERE oid = event_info.relation INTO rel;

  RAISE DEBUG 'Column % drop by % (superuser? %) in relation % of kind %',
	 (event_info.old).attname, current_user, current_setting('is_superuser'), event_info.relation::regclass, rel.relkind;

  -- We're only interested in real relations
  IF rel.relkind != 'r' THEN RETURN; END IF;

  -- We don't want to react to drops triggered by superuser,
  IF current_setting('is_superuser') = 'on' THEN
    RAISE DEBUG 'no ddl trigger for superuser';
    RETURN;
  END IF;

  PERFORM cdb_disable_ddl_hooks();

  PERFORM public.CDB_CartodbfyTable(event_info.relation);

  PERFORM cdb_enable_ddl_hooks();

  -- TODO: invalidate varnish 

END; $$;
-- }

-- Column add
-- {
CREATE OR REPLACE FUNCTION cdb_handle_add_column ()
RETURNS event_trigger SECURITY DEFINER LANGUAGE plpgsql AS $$
DECLARE
  event_info RECORD;
  rel RECORD;
BEGIN
  event_info := schema_triggers.get_column_add_eventinfo();

  SELECT oid,* FROM pg_class WHERE oid = event_info.relation INTO rel;

  RAISE DEBUG 'Column % added by % (superuser? %) in relation % of kind %',
	 (event_info.new).attname, current_user, current_setting('is_superuser'), event_info.relation::regclass, rel.relkind;

  -- We're only interested in real relations
  IF rel.relkind != 'r' THEN RETURN; END IF;

  -- We don't want to react to drops triggered by superuser,
  IF current_setting('is_superuser') = 'on' THEN
    RAISE DEBUG 'no ddl trigger for superuser';
    RETURN;
  END IF;

  -- TODO: invalidate varnish

END; $$;
-- }

CREATE OR REPLACE FUNCTION cdb_disable_ddl_hooks() returns void AS $$
 DROP EVENT TRIGGER IF EXISTS cdb_on_relation_create;
 DROP EVENT TRIGGER IF EXISTS cdb_on_alter_column;
 DROP EVENT TRIGGER IF EXISTS cdb_on_drop_column;
 DROP EVENT TRIGGER IF EXISTS cdb_on_add_column;
$$ LANGUAGE sql;

CREATE OR REPLACE FUNCTION cdb_enable_ddl_hooks() returns void AS $$
 SELECT cdb_disable_ddl_hooks();
 CREATE EVENT TRIGGER cdb_on_relation_create ON "relation_create" EXECUTE PROCEDURE cdb_handle_create_table();
 CREATE EVENT TRIGGER cdb_on_alter_column ON "column_alter" EXECUTE PROCEDURE cdb_handle_alter_column();
 CREATE EVENT TRIGGER cdb_on_drop_column ON "column_drop" EXECUTE PROCEDURE cdb_handle_drop_column();
 CREATE EVENT TRIGGER cdb_on_add_column ON "column_add" EXECUTE PROCEDURE cdb_handle_add_column();
$$ LANGUAGE sql;

SELECT cdb_enable_ddl_hooks();

END;

