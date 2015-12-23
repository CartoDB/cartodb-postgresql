# Ruby script to generate test/overviews/fixtures.sql for testing overviews
# Generated tables:
# * base_bare_t -- points without attributes (only PK, geometries)

NUM_CLUSTERS = 128
MAX_PER_CLUSTER = 16
CLUSTER_RADIUS = 1E-3
MIN_X = -10.0
MAX_X =  10.0
MIN_Y =  30.0
MAX_Y = 40.0
ATTRIBUTES = "number double precision, int_number integer, name text, start date"

id = 0
POINTS = (0...NUM_CLUSTERS).map{
  x = MIN_X + rand()*(MAX_X - MIN_X)
  y = MIN_Y + rand()*(MAX_Y - MIN_Y)
  (0..rand(MAX_PER_CLUSTER)).map{
    id += 1
    {
      id: id,
      x: (x + rand()*CLUSTER_RADIUS).round(6),
      y: (y + rand()*CLUSTER_RADIUS).round(6)
    }
  }
}.flatten

values = POINTS.map{ |point|
  "#{point[:id]}, 'SRID=4326;POINT(#{point[:x]} #{point[:y]})'::geometry, ST_Transform('SRID=4326;POINT(#{point[:x]} #{point[:y]})'::geometry, 3857)"
}

File.open('fixtures.sql', 'w') do |sql|

  sql.puts "-- bare table with no attribute columns"
  sql.puts "CREATE TABLE base_bare_t (cartodb_id integer, the_geom geometry, the_geom_webmercator geometry);"
  sql.puts "INSERT INTO base_bare_t VALUES"
  sql.puts values.map{|v| "(#{v})"}.join(",\n") + ";"

  sql.puts "-- table with attributes"
  sql.puts "CREATE TABLE base_t (cartodb_id integer, the_geom geometry, the_geom_webmercator geometry, #{ATTRIBUTES});"
  sql.puts "INSERT INTO base_t VALUES"
  sql.puts values.map{|v| "(#{v})"}.join(",\n") + ";"
end
