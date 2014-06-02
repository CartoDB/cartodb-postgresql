-- Function that setups user's domain, port and http/https inside his own DB.
-- Used for HTTP table sync functions.
CREATE OR REPLACE FUNCTION CDB_SetUserDomain(domain text, port int8, secure boolean)
RETURNS VOID AS
$$
DECLARE
  sql TEXT;
BEGIN
  sql := 'CREATE OR REPLACE FUNCTION public._CDB_UserDomain() '
    || ' RETURNS TABLE (domain text, port int8, secure boolean) '
    || ' AS $X$ '
    || ' SELECT ''' || domain || '''::text, ' || port || '::int8, ' || secure || '::boolean '
    || ' $X$ LANGUAGE sql IMMUTABLE';
  EXECUTE sql;
  RETURN;
END
$$
LANGUAGE 'plpgsql' VOLATILE STRICT;