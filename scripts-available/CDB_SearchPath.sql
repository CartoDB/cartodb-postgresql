---- Make sure '@extschema@' is in database search path
DO
$$
DECLARE
  var_result text;
  var_cur_search_path text;
BEGIN
  SELECT reset_val INTO var_cur_search_path
  FROM pg_settings WHERE name = 'search_path';

  IF var_cur_search_path LIKE '%@extschema@%' THEN
    RAISE DEBUG '"@extschema@" already in database search_path';
  ELSE
    var_cur_search_path := var_cur_search_path || ', "@extschema@"';
    EXECUTE 'ALTER DATABASE ' || quote_ident(current_database()) ||
            ' SET search_path = ' || var_cur_search_path;
    RAISE DEBUG '"@extschema@" has been added to end of database search_path';
  END IF;

  -- Reset search_path
  EXECUTE 'SET search_path = ' || var_cur_search_path;

END
$$ LANGUAGE 'plpgsql';
