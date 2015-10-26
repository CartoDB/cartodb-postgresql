-- UTF8 safe and lenght aware. Find a unique identifier with a given prefix
-- and/or suffix and withing a schema. If a schema is not specified, the identifier
-- is guaranteed to be unique for all schemas.
CREATE OR REPLACE FUNCTION cartodb._CDB_Unique_Identifier(prefix TEXT, relname TEXT, suffix TEXT, schema TEXT DEFAULT NULL)
RETURNS TEXT
AS $$
DECLARE
  maxlen CONSTANT INTEGER := 63;

  rec RECORD;
  usedspace INTEGER;
  ident TEXT;
  origident TEXT;

  i INTEGER;
BEGIN
  -- Accounts for the _XX incremental suffix in case the identifier is taken
  usedspace := 3;
  usedspace := usedspace + coalesce(octet_length(prefix), 0);
  usedspace := usedspace + coalesce(octet_length(suffix), 0);

  relname := _CDB_Octet_Truncate(relname, maxlen - usedspace);

  IF relname = '' THEN
    PERFORM _CDB_Error('prefixes are to long to generate a valid identifier', '_CDB_Unique_Identifier');
  END IF;

  ident := coalesce(prefix, '') || relname || coalesce(suffix, '');

  i := 0;
  origident := ident;

  WHILE i < 100 LOOP
    IF schema IS NOT NULL THEN
      SELECT c.relname, n.nspname
      INTO rec
      FROM pg_class c
      JOIN pg_namespace n ON c.relnamespace = n.oid
      WHERE c.relname = ident
      AND n.nspname = schema;
    ELSE
      SELECT c.relname, n.nspname
      INTO rec
      FROM pg_class c
      JOIN pg_namespace n ON c.relnamespace = n.oid
      WHERE c.relname = ident;
    END IF;

    IF NOT FOUND THEN
      RETURN ident;
    END IF;

    ident := origident || '_' || i;
    i := i + 1;
  END LOOP;

  PERFORM _CDB_Error('looping too far', '_CDB_Unique_Identifier');
END;
$$ LANGUAGE 'plpgsql';


-- UTF8 safe and lenght aware. Find a unique identifier for a column with a given prefix
-- and/or suffix and withing a realtion.
CREATE OR REPLACE FUNCTION cartodb._CDB_Unique_Column_Identifier(prefix TEXT, relname TEXT, suffix TEXT, reloid REGCLASS)
RETURNS TEXT
AS $$
DECLARE
  maxlen CONSTANT INTEGER := 63;

  rec RECORD;
  usedspace INTEGER;
  ident TEXT;
  origident TEXT;

  i INTEGER;
BEGIN
  -- Accounts for the _XX incremental suffix in case the identifier is taken
  usedspace := 3;
  usedspace := usedspace + coalesce(octet_length(prefix), 0);
  usedspace := usedspace + coalesce(octet_length(suffix), 0);

  relname := _CDB_Octet_Truncate(relname, maxlen - usedspace);

  IF relname = '' THEN
    PERFORM _CDB_Error('prefixes are to long to generate a valid identifier', '_CDB_Unique_Column_Identifier');
  END IF;

  ident := coalesce(prefix, '') || relname || coalesce(suffix, '');

  i := 0;
  origident := ident;

  WHILE i < 100 LOOP
    SELECT a.attname
    INTO rec
    FROM pg_class c
    JOIN pg_attribute a ON a.attrelid = c.oid
    WHERE NOT a.attisdropped
    AND a.attnum > 0
    AND c.oid = reloid
    AND a.attname = ident;

    IF NOT FOUND THEN
      RETURN ident;
    END IF;

    ident := origident || '_' || i;
    i := i + 1;
  END LOOP;

  PERFORM _CDB_Error('looping too far', '_CDB_Unique_Column_Identifier');
END;
$$ LANGUAGE 'plpgsql';


-- Truncates a given string to a max_octets octexts taking care
-- not to leave characters in half. UTF8 safe.
CREATE OR REPLACE FUNCTION cartodb._CDB_Octet_Truncate(string TEXT, max_octets INTEGER)
RETURNS TEXT
AS $$
DECLARE
  extcharlen CONSTANT INTEGER := octet_length('ñ');

  expected INTEGER;
  examined INTEGER;
  strlen INTEGER;

  i INTEGER;
BEGIN

  IF max_octets <= 0 THEN
    RETURN '';
  ELSIF max_octets >= octet_length(string) THEN
    RETURN string;
  END IF;

  strlen := char_length(string);

  expected := char_length(string);
  examined := octet_length(string);

  IF expected = examined THEN
    RETURN SUBSTRING(string from 1 for max_octets);
  END IF;

  i := max_octets / extcharlen;

  WHILE octet_length(SUBSTRING(string from 1 for i)) <= max_octets LOOP
    i := i + 1;
  END LOOP;

  RETURN SUBSTRING(string from 1 for (i - 1));
END;
$$ LANGUAGE 'plpgsql';