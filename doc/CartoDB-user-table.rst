CartoDB User Table
==================

Introduction
----------
A CartoDB user table is a table with a well-known set of columns and a well-known set of triggers attached on.

Columns
----------
The required columns of a CartoDB table are:

-  ``cartodb_id``
  - This column will be used as the primary key of the table and it has a sequence as default value
  - Its values must be integer, non-zero, non-null and unique
  -  B-Tree indexed
-  ``the_geom``
  - This column stores the main geometric features of a table
  - The type of the column in the Postgres database is ``geometry(Geometry,4326)```
  - GiST indexed
  -  geometry, GiST indexed, constrained (see below)
-  ``the_geom_webmercator``
  - This column stores the geometries used for rendering purposes
  - The type of the column in the Postgres database is ``geometry(Geometry,3857)``
  - GiST indexed
  - This column is automatically updated by the system when the ``the_geom`` column is updated or when there is an insertion of a new row into the table (See triggers below)

The values of ``the_geom`` and ``the_geom_webmercator`` must be two-dimensional Points, MultiLineStrings or MultiPolygons. Different geometric types in a CartoDB table are not supported.

Described table example
^^^^^^^^^^
::

        Column        |          Type           |                       Modifiers                        
  ----------------------+-------------------------+--------------------------------------------------------
   cartodb_id           | bigint                  | not null default nextval('t_cartodb_id_seq'::regclass)
   the_geom             | geometry(Geometry,4326) | 
   the_geom_webmercator | geometry(Geometry,3857) | 
  Indexes:
      "table_name_pkey" PRIMARY KEY, btree (cartodb_id)
      "table_name_the_geom_idx" gist (the_geom)
      "table_name_the_geom_webmercator_idx" gist (the_geom_webmercator)

Triggers
----------
The triggers generated in each CartoDB table are:

-  ``track_updates`` after modifying statement updates ``cdb_tablemetadata``
-  ``test_quota`` before changing statement to forbid if overquota
-  ``test_quota_per_row`` before insert ot update row to forbid if overquota (checked on a probabilistic basis)
-  ``update_the_geom_webmercator`` before insert or update row to maintain the ``the_geom_webmercator`` updated with the contents in ``the_geom``

Described triggers example
^^^^^^^^^^
::

  test_quota BEFORE INSERT OR UPDATE ON t FOR EACH STATEMENT EXECUTE PROCEDURE cdb_checkquota('0.1', '-1', 'public')
  test_quota_per_row BEFORE INSERT OR UPDATE ON t FOR EACH ROW EXECUTE PROCEDURE cdb_checkquota('0.001', '-1', 'public')
  track_updates AFTER INSERT OR DELETE OR UPDATE OR TRUNCATE ON t FOR EACH STATEMENT EXECUTE PROCEDURE cdb_tablemetadata_trigger()
  update_the_geom_webmercator_trigger BEFORE INSERT OR UPDATE OF the_geom ON t FOR EACH ROW EXECUTE PROCEDURE _cdb_update_the_geom_webmercator()


Further details
----------

Some conversions will be attempted to perform upon cartodbfication when certain fields appear:

-  ``cartodb_id``: If found type TEXT will be attempted to cast to integer. If not casteable, an eror will be raised.
-  ``the_geom``: If found type TEXT will be attempted to cast to geometry(Geometry,4326).
