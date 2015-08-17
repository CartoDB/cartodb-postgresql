A "cartodb" user table is a table with a well-known set of fields and a well-known set of triggers attached on. 

The fields are:

 - `cartodb_id`, a numerical primary key of serial type
 - `created_at`, timestamp with timezone not null default now()
 - `updated_at`, timestamp with timezone not null default now()
 - `the_geom`, geometry, GiST indexed, constrained (see below)
 - `the_geom_webmercator`, geometry, GiST indexed, constrained (see below)

The values of "the_geom" and "the_geom_webmercator" must match these constraints:

 - Only POINT, MULTILINE, MULTIPOLYGON types ? Maybe UNCONSTRAINED
 - Only 2 dimensions ? Maybe UNCONSTRAINED
 - SRID=4326 for the_geom and SRID=3857 for the_geom_webmercator

The triggers are:

 - `track_updates` after modifying statement updates cdb_tablemetadata
 - `test_quota` before changing statement to forbid if overquota
 - `test_quota_per_row` before changing row to forbod if overquota (checked on a probabilistic basis)
 - `update_the_geom_webmercator` before insert or update row to maintain the_geom_webmercator
 - `update_updated_at_trigger` before update row to maintain updated_at

Some conversions will be attempted to perform upon cartodbfication when certain fields appear:

 - `cartodb_id`: If found type TEXT will be attempted to cast
 - `created_at`: If found type TEXT will be attempted to cast
 - `updated_at`: If found type TEXT will be attempted to cast