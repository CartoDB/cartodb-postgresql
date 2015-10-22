-- UTF8 safe and lenght aware. Find a unique identifier with a given prefix
-- and/or suffix and withing a schema.
CREATE OR REPLACE FUNCTION cartodb.CDB_Unique_Identifier(prefix TEXT, relname TEXT, suffix TEXT, schema TEXT DEFAULT NULL)
RETURNS TEXT
AS $$
DECLARE
  rec RECORD;
  usedspace INTEGER;
  ident TEXT;
  i INTEGER;
  origident TEXT;
  maxlen INTEGER;
BEGIN
  maxlen := 63;

  usedspace := 3;
  usedspace := usedspace + coalesce(octet_length(prefix), 0);
  usedspace := usedspace + coalesce(octet_length(suffix), 0);

  relname := CDB_Octet_Trim(relname, usedspace + octet_length(relname) - maxlen);

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


-- Trims the end of a given string by the given number of octets taking care
-- not to leave characters in half. UTF8 safe.
CREATE OR REPLACE FUNCTION cartodb.CDB_Octet_Trim(tostrip TEXT, octets INTEGER)
RETURNS TEXT
AS $$
DECLARE
  expected INTEGER;
  examined INTEGER;
  tostriplen INTEGER;
  charlen INTEGER;

  i INTEGER;
  tail TEXT;

  trimmed TEXT;
BEGIN
  charlen := bit_length('a');
  tostriplen := char_length(tostrip);
  expected := tostriplen * charlen;
  examined := bit_length(tostrip);

  IF expected = examined OR octets = 0 THEN
    RETURN SUBSTRING(tostrip from 1 for (tostriplen - octets));
  ELSIF octets < 0 THEN
    RETURN tostrip;
  ELSIF (octets * charlen) > examined THEN
    RETURN '';
  END IF;

  i := tostriplen - ((octets - 1) / 2);
  LOOP
    tail := SUBSTRING(tostrip from i for tostriplen);

    EXIT WHEN octet_length(tail) >= octets OR i <= 0;

    i := i - 1;
  END LOOP;

  trimmed := SUBSTRING(tostrip from 1 for (tostriplen - char_length(tail)));
  RETURN trimmed;
END;
$$ LANGUAGE 'plpgsql';

