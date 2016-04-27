CartoDBfy Requirements
======================

Introduction
------------

This document aims at describing what the CartoDBfication is and what its formal requirements are, with the following goals in mind:

- Clarify what are the expectations of the "cartodbfycation process".
- Define an important part of what should be a stable, public API
- Allow for better testing, which should in turn...
- ...ease modifications and increase quality of the code


What is the CartoDBfycation
---------------------------

The CartoDBfycation is the process of converting an arbitrary postgres table into a valid CartoDB table, and register it in the system so that it can be used in the CartoDB editor and platform to generate maps and analysis.

It is performed by running the function ``CDB_CartodbfyTable(reloid REGCLASS)`` over a target table.

Valid CartoDB tables
--------------------

A valid CartoDB table shall meet the following conditions:

- Have a ``cartodb_id`` column with integer, unique, non-zero and non-null values as primary key with a sequence as default value
- Have a ``the_geom`` column of type ``Geometry`` with SRID 4326
- Have a ``the_geom_webmercator`` column of type ``Geometry`` with SRID 3857
- The columns ``the_geom`` and ``the_geom_webmercator`` shall be in sync (task of the ``update_the_geom_webmercator`` trigger)

Additionally, a CartoDB table can contain other columns.

See the `CartoDB User Table documentation`_

.. _CartoDB User Table documentation: https://github.com/CartoDB/cartodb-postgresql/blob/master/doc/CartoDB-user-table.rst 
for further information.

High level requirements
-----------------------

Here is a list of high level requirments for the public function ``CDB_CartodbfyTable()``:

- A call to the function shall modify/rewrite the table and produce a valid CartoDB table with the same name.
- A call to the function shall cause the registration of the table into the platform.
- It shall be idempotent, meaning that successive calls to the function shall not produce any visible effect in the system.
- If there's a column containing a geometry, it shall be used to generate ``the_geom`` and the ``the_geom_webmercator`` columns.
- Exporting and re-importing the same table in CartoDB shall produce equivalent tables, with the same features associated to the same ``cartodb_id``'s.


Note that there should be only one geometry per row in the source table. If there's more than one, then which one is used for ``the_geom`` and ``the_geom_webmercator`` fields is not determined.


Low-level requirements
----------------------

- If the original table contains a valid (integer, unique, non-zero and not null) ``cartodb_id`` column, it shall be used
- If the original table contains a ``the_geom`` column or a ``the_geom_webmercator`` geometric column in the expected projection (EPSG 4326 and EPSG 3857, respectively) they shall be used.
- A modification of a cartodbfy'ed table shall insert or update a row in ``CDB_TableMetadata``
- A cartodbfy'ed table shall have a ``btree`` index on ``cartodb_id``
- A cartodbfy'ed table shall have ``gist`` indices on ``the_geom`` and ``the_geom_webmercator``
- Cartodbfy shall deal with text columns for imports, regarding CartoDB columns (``cartodb_id``, ``the_geom``, ``the_geom_webmercator``)

