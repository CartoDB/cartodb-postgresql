CREATE OR REPLACE FUNCTION cartodb.CDB_ZoomFromScale(scaleDenominator numeric) RETURNS int AS $$
BEGIN
  CASE
    WHEN scaleDenominator > 500000000 THEN RETURN 0;
    WHEN scaleDenominator <= 500000000 AND scaleDenominator > 200000000 THEN RETURN 1;
    WHEN scaleDenominator <= 200000000 AND scaleDenominator > 100000000 THEN RETURN 2;
    WHEN scaleDenominator <= 100000000 AND scaleDenominator > 50000000 THEN RETURN 3;
    WHEN scaleDenominator <= 50000000 AND scaleDenominator > 25000000 THEN RETURN 4;
    WHEN scaleDenominator <= 25000000 AND scaleDenominator > 12500000 THEN RETURN 5;
    WHEN scaleDenominator <= 12500000 AND scaleDenominator > 6500000 THEN RETURN 6;
    WHEN scaleDenominator <= 6500000 AND scaleDenominator > 3000000 THEN RETURN 7;
    WHEN scaleDenominator <= 3000000 AND scaleDenominator > 1500000 THEN RETURN 8;
    WHEN scaleDenominator <= 1500000 AND scaleDenominator > 750000 THEN RETURN 9;
    WHEN scaleDenominator <= 750000 AND scaleDenominator > 400000 THEN RETURN 10;
    WHEN scaleDenominator <= 400000 AND scaleDenominator > 200000 THEN RETURN 11;
    WHEN scaleDenominator <= 200000 AND scaleDenominator > 100000 THEN RETURN 12;
    WHEN scaleDenominator <= 100000 AND scaleDenominator > 50000 THEN RETURN 13;
    WHEN scaleDenominator <= 50000 AND scaleDenominator > 25000 THEN RETURN 14;
    WHEN scaleDenominator <= 25000 AND scaleDenominator > 12500 THEN RETURN 15;
    WHEN scaleDenominator <= 12500 AND scaleDenominator > 5000 THEN RETURN 16;
    WHEN scaleDenominator <= 5000 AND scaleDenominator > 2500 THEN RETURN 17;
    WHEN scaleDenominator <= 2500 AND scaleDenominator > 1500 THEN RETURN 18;
    WHEN scaleDenominator <= 1500 AND scaleDenominator > 750 THEN RETURN 19;
    WHEN scaleDenominator <= 750 AND scaleDenominator > 500 THEN RETURN 20;
    WHEN scaleDenominator <= 500 AND scaleDenominator > 250 THEN RETURN 21;
    WHEN scaleDenominator <= 250 AND scaleDenominator > 100 THEN RETURN 22;
    WHEN scaleDenominator <= 100 THEN RETURN 23;
  END CASE;
END
$$ LANGUAGE plpgsql IMMUTABLE;
