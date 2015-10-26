-- UTF8 safe and lenght aware. Find a unique identifier with a given prefix
-- and/or suffix and withing a schema. If a schema is not specified, the identifier
-- is guaranteed to be unique for all schemas.
CREATE OR REPLACE FUNCTION cartodb._CDB_Unique_Identifier(prefix TEXT, relname TEXT, suffix TEXT, schema TEXT DEFAULT NULL)
RETURNS TEXT
AS $$
DECLARE
  rec RECORD;
  usedspace INTEGER;
  ident TEXT;
  i INTEGER;
  origident TEXT;

  maxlen CONSTANT integer := 63;
BEGIN
  -- Accounts for the _XX incremental suffix in case the identifier is taken
  usedspace := 3;
  usedspace := usedspace + coalesce(octet_length(prefix), 0);
  usedspace := usedspace + coalesce(octet_length(suffix), 0);

  relname := _CDB_Trim_Octets(relname, usedspace + octet_length(relname) - maxlen);

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
  rec RECORD;
  usedspace INTEGER;
  ident TEXT;
  i INTEGER;
  origident TEXT;

  maxlen CONSTANT integer := 63;
BEGIN
  -- Accounts for the _XX incremental suffix in case the identifier is taken
  usedspace := 3;
  usedspace := usedspace + coalesce(octet_length(prefix), 0);
  usedspace := usedspace + coalesce(octet_length(suffix), 0);

  relname := _CDB_Trim_Octets(relname, usedspace + octet_length(relname) - maxlen);

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

-- Trims the end of a given string by the given number of octets taking care
-- not to leave characters in half. If a negative or 0 amount of octects to trim
-- is specified, the suplied text is returned unaltered. UTF8 safe.
CREATE OR REPLACE FUNCTION cartodb._CDB_Trim_Octets(totrim TEXT, octets INTEGER)
RETURNS TEXT
AS $$
DECLARE
  expected INTEGER;
  examined INTEGER;
  totrimlen INTEGER;
  charlen INTEGER;

  i INTEGER;
  tail TEXT;

  trimmed TEXT;
BEGIN
  charlen := bit_length('a');
  totrimlen := char_length(totrim);
  expected := totrimlen * charlen;
  examined := bit_length(totrim);

  IF octets <= 0 THEN
    RETURN totrim;
  ELSIF expected = examined THEN
    RETURN SUBSTRING(totrim from 1 for (totrimlen - octets));
  ELSIF (octets * charlen) > examined THEN
    RETURN '';
  END IF;

  i := totrimlen - ((octets - 1) / 2);
  LOOP
    tail := SUBSTRING(totrim from i for totrimlen);

    EXIT WHEN octet_length(tail) >= octets OR i <= 0;

    i := i - 1;
  END LOOP;

  trimmed := SUBSTRING(totrim from 1 for (totrimlen - char_length(tail)));
  RETURN trimmed;
END;
$$ LANGUAGE 'plpgsql';

