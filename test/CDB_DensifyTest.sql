with data as (
    select
    ARRAY[7.0,8.0,1.0,2.0,3.0,5.0,6.0,4.0] as colin,
    ARRAY[ST_GeomFromText('POINT(2.1744 41.4036)'),ST_GeomFromText('POINT(2.1228 41.3809)'),ST_GeomFromText('POINT(2.1511 41.3742)'),ST_GeomFromText('POINT(2.1528 41.4136)'),ST_GeomFromText('POINT(2.165 41.3917)'),ST_GeomFromText('POINT(2.1498 41.3713)'),ST_GeomFromText('POINT(2.1533 41.3683)'),ST_GeomFromText('POINT(2.131386 41.413998)')] as geomin
)
select CDB_Densify(geomin, colin, 2) from data;
