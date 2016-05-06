--
-- Calculate the DevStd bins for a given column
--
-- @param in_array A numeric array of numbers to determine the best
--                   to determine the bin boundary
--
--
-- Returns: upper edges of bins
--
--

CREATE OR REPLACE FUNCTION CDB_StdDevBins(in_array NUMERIC[]) RETURNS NUMERIC[] as $$
DECLARE
    reply numeric[];
BEGIN
    WITH a as(
        SELECT unnest(in_array) e
    ),
    b as(
        select a.e,
        TRUNC((AVG(a.e) - AVG(AVG(a.e)) OVER ()) / trunc((STDDEV(AVG(a.e)) OVER ())::numeric, 5) ) AS Bucket
        from a
        group by a.e
    ),
    c as(
        select
        max(b.e) as mx
        from b
        group by bucket
        order by bucket
    )
    select array_agg(mx) into reply from c;
    RETURN reply;
END;
$$ language plpgsql IMMUTABLE;
