-- Table to register analysis nodes from https://github.com/cartodb/camshaft
CREATE TABLE IF NOT EXISTS
@extschema@.cdb_analysis_catalog (
    -- md5 hex hash
    node_id char(40) CONSTRAINT cdb_analysis_catalog_pkey PRIMARY KEY,
    -- being json allows to do queries like analysis_def->>'type' = 'buffer'
    analysis_def json NOT NULL,
    -- can reference other nodes in this very same table, allowing recursive queries
    input_nodes char(40) ARRAY NOT NULL DEFAULT '{}',
    status TEXT NOT NULL DEFAULT 'pending',
    CONSTRAINT valid_status CHECK (
        status IN ( 'pending', 'waiting', 'running', 'canceled', 'failed', 'ready' )
    ),
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    -- should be updated when some operation was performed in the node
    -- and anything associated to it might have changed
    updated_at timestamp with time zone DEFAULT NULL,
    -- should register last time the node was used
    used_at timestamp with time zone NOT NULL DEFAULT now(),
    -- should register the number of times the node was used
    hits NUMERIC DEFAULT 0,
    -- should register what was the last node using current node
    last_used_from char(40),
    -- last job modifying the node
    last_modified_by uuid,
    -- store error message for failures
    last_error_message text,
    -- cached tables involved in the analysis
    cache_tables regclass[] NOT NULL DEFAULT '{}',
    -- useful for multi account deployments
    username text
);

-- This can only be called from an SQL script executed by CREATE EXTENSION
DO LANGUAGE 'plpgsql' $$
BEGIN
    PERFORM pg_catalog.pg_extension_config_dump('@extschema@.cdb_analysis_catalog', '');
END
$$;

-- Migrations to add new columns from old versions.
-- IMPORTANT: Those columns will be added in order of creation. To be consistent
-- in column order, ensure that new columns are added at the end and in the same order.

DO $$
    BEGIN
        BEGIN
            ALTER TABLE @extschema@.cdb_analysis_catalog ADD COLUMN last_modified_by uuid;
        EXCEPTION
            WHEN duplicate_column THEN END;
    END;
$$;

DO $$
    BEGIN
        BEGIN
            ALTER TABLE @extschema@.cdb_analysis_catalog ADD COLUMN last_error_message text;
        EXCEPTION
            WHEN duplicate_column THEN END;
    END;
$$;

DO $$
    BEGIN
        BEGIN
            ALTER TABLE @extschema@.cdb_analysis_catalog ADD COLUMN cache_tables regclass[] NOT NULL DEFAULT '{}';
        EXCEPTION
            WHEN duplicate_column THEN END;
    END;
$$;

DO $$
    BEGIN
        BEGIN
            ALTER TABLE @extschema@.cdb_analysis_catalog ADD COLUMN username text;
        EXCEPTION
            WHEN duplicate_column THEN END;
    END;
$$;

-- We want the "username" column to be moved to the last position if it was on a position from other versions
-- see https://github.com/CartoDB/cartodb-postgresql/issues/276
DO LANGUAGE 'plpgsql' $$
    DECLARE
        column_index int;
    BEGIN
        SELECT ordinal_position FROM information_schema.columns WHERE table_name='cdb_analysis_catalog' AND table_schema='@extschema@' AND column_name='username' INTO column_index;
        IF column_index = 1 OR column_index = 10 THEN
           ALTER TABLE @extschema@.cdb_analysis_catalog ADD COLUMN username_final text;
           UPDATE @extschema@.cdb_analysis_catalog SET username_final = username;
           ALTER TABLE @extschema@.cdb_analysis_catalog DROP COLUMN username;
           ALTER TABLE @extschema@.cdb_analysis_catalog RENAME COLUMN username_final TO username;
        END IF;
    END;
$$;
