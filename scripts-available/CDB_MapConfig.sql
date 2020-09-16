-- Table to save map configs
CREATE TABLE IF NOT EXISTS
@extschema@.CDB_MapConfig (
  id char(32) not null primary key,
  map jsonb not null, 
  used_at timestamp with time zone NOT NULL DEFAULT now()
);

-- trigger function which updates the last day date 
-- only when the current date is older than 1 day
CREATE OR REPLACE FUNCTION @extschema@._CDB_MapConfig_Update_Used_At()
  RETURNS trigger 
AS $$
BEGIN
  IF NEW."used_at" < (now() - '1 days'::interval) THEN
    NEW."used_at" = NOW();
    RETURN NEW;
  END IF;
END;
$$ LANGUAGE plpgsql VOLATILE PARALLEL UNSAFE;

--  create trigger
DROP TRIGGER IF EXISTS update_used_at ON @extschema@.CDB_MapConfig;
CREATE TRIGGER update_used_at 
AFTER SELECT ON @extschema@.CDB_MapConfig 
FOR EACH ROW EXECUTE PROCEDURE @extschema@._CDB_MapConfig_Update_Used_At();


-- trigger function which removes the latest map config
-- if the date is older than 30 days
CREATE OR REPLACE FUNCTION @extschema@._CDB_MapConfig_Remove_Latest_One()
  RETURNS trigger 
AS $$
BEGIN
  SELECT id 
  FROM @extschema@.CDB_MapConfig
  WHERE used_at < (now() - '30 days'::interval)
  ORDER BY used_at ASC
  LIMIT 1 
  INTO map_id;

  IF map_id IS NOT NULL THEN
    DELETE FROM @extschema@.CDB_MapConfig
    WHERE id = map_id;
  END IF;

END;
$$ LANGUAGE plpgsql VOLATILE PARALLEL UNSAFE;

--  create trigger
DROP TRIGGER IF EXISTS remove_latest_one ON @extschema@.CDB_MapConfig;
CREATE TRIGGER remove_latest_one 
BEFORE INSERT ON @extschema@.CDB_MapConfig 
FOR EACH STATEMENT EXECUTE PROCEDURE @extschema@._CDB_MapConfig_Remove_Latest_One();



