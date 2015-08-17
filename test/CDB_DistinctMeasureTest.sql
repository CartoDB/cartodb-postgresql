-- a - j add up to 89%, k-m add up to 11%
WITH a As (
	SELECT (
		repeat('a',12) || 
		repeat('b',11) || 
		repeat('c',11) || 
		repeat('d',10) || 
		repeat('e',10) || 
		repeat('f',9) || 
		repeat('g',8) || 
		repeat('h',7) || 
		repeat('i',6) || 
		repeat('j',5) || 
		repeat('k',4) || 
		repeat('l',4) || 
		repeat('m',3)
		)::text AS x 
	) 

SELECT CDB_DistinctMeasure(string_to_array(x,null),0.90) from a
