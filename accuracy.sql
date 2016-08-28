--add statement that converts to utm if in latlon (to maintain the result
-- is in meters)

                
DROP TABLE IF EXISTS extracted_line_single;
CREATE TABLE extracted_line_single AS (
SELECT extracted_line.gid, extracted_line.id,
      (ST_Dump(extracted_line.geom)).geom AS geom
FROM extracted_line);
ALTER TABLE extracted_line_single ADD COLUMN gid_pk BIGSERIAL PRIMARY KEY;

DROP TABLE IF EXISTS reference_line_single;
CREATE TABLE reference_line_single AS (
SELECT reference_line.gid, reference_line.id,
      (ST_Dump(reference_line.geom)).geom AS geom
FROM reference_line);
ALTER TABLE reference_line_single ADD COLUMN gid_pk BIGSERIAL PRIMARY KEY;

DROP TABLE IF EXISTS reference_buffered;
CREATE TABLE reference_buffered AS (
  SELECT reference_line_single.gid, reference_line_single.id, gid_pk,
  ST_Buffer(geom, 10) AS geom
  FROM reference_line_single
);
--ALTER TABLE reference_buffered ADD COLUMN gid_pk BIGSERIAL PRIMARY KEY;

DROP TABLE IF EXISTS extracted_buffered;
CREATE TABLE extracted_buffered AS (
  SELECT extracted_line_single.gid, extracted_line_single.id, gid_pk,
  ST_Buffer(geom, 10) AS geom
  FROM extracted_line_single
);
--ALTER TABLE extracted_buffered ADD COLUMN gid_pk BIGSERIAL PRIMARY KEY;


-- There are double geometries in false positives
DROP TABLE IF EXISTS true_positives;
CREATE TABLE true_positives AS (
SELECT extracted_line_single.gid, extracted_line_single.id, 
ST_Length(ST_Intersection(extracted_line_single.geom,reference_buffered.geom)) AS length,
ST_Intersection(extracted_line_single.geom,reference_buffered.geom) as geom
FROM extracted_line_single, reference_buffered
WHERE ST_Intersects(extracted_line_single.geom,reference_buffered.geom)='t' 
	);
ALTER TABLE true_positives ADD COLUMN gid_pk BIGSERIAL PRIMARY KEY;

--xxxxxxxxxxxxxxxxxxxxxxxxxxxxx
DROP TABLE IF EXISTS true_positives_single;
CREATE TABLE true_positives_single AS (
SELECT true_positives.gid, true_positives.id,
true_positives.length,
      (ST_Dump(true_positives.geom)).geom AS geom
FROM true_positives);

--xxxxxxxxxxxxxxxxxxxxxxxxxxxxx

DROP TABLE IF EXISTS false_positives;
CREATE TABLE false_positives AS (
SELECT extracted_line_single.gid,
ST_Difference(extracted_line_single.geom, reference_buffered.geom) as geom
FROM extracted_line_single, reference_buffered
WHERE ST_Intersects(extracted_line_single.geom,reference_buffered.geom)='t'
);
ALTER TABLE false_positives ADD COLUMN length double precision;
UPDATE false_positives SET length = st_length(geom);

DROP TABLE IF EXISTS false_negatives;
CREATE TABLE false_negatives AS (
SELECT reference_line_single.gid, reference_line_single.id,
ST_Difference(reference_line_single.geom, extracted_buffered.geom) as geom
FROM reference_line_single, extracted_buffered
WHERE ST_Intersects(reference_line_single.geom,extracted_buffered.geom)='t'
);
ALTER TABLE false_negatives ADD COLUMN length double precision;
UPDATE false_negatives SET length = st_length(geom);

DROP TABLE IF EXISTS accuracy;
CREATE TABLE accuracy (
	completeness REAL,
	correctness REAL,
	quality REAL
	);

CREATE OR REPLACE FUNCTION calculate_accuracy()
RETURNS TABLE (completeness real, correctness real, accuracy real) AS

$$
DECLARE TP real := SUM(true_positives.length) from true_positives;
DECLARE FP real := SUM(false_positives.length) from false_positives;
DECLARE FN real := SUM(false_negatives.length) from false_negatives;
DECLARE completeness real:= TP/(TP + FN);
DECLARE correctness real:= TP/(TP + FP);
DECLARE quality real:= TP/(TP + FP + FN);

BEGIN
INSERT INTO accuracy VALUES(
completeness, correctness, quality);
	RETURN QUERY
	SELECT * FROM accuracy;
END;

$$ 
LANGUAGE plpgsql;

SELECT calculate_accuracy();


