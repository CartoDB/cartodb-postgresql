DO LANGUAGE 'plpgsql' $$
BEGIN
  IF NOT EXISTS ( SELECT * FROM pg_roles WHERE rolname= 'cdb_org_admin' )
  THEN
    CREATE ROLE cdb_org_admin NOLOGIN;
  END IF;

  IF NOT EXISTS ( SELECT * FROM pg_roles WHERE rolname= 'cdb_org_user' )
  THEN
    CREATE ROLE cdb_org_user NOLOGIN;
  END IF;
END
$$;
