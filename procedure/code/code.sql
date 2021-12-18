
--create centroids for buildings that aren't hospitals or clinics
CREATE TABLE buildingcentroids AS
SELECT osm_id, amenity, name, st_transform(st_centroid(way),32737)::geometry(point,32737) AS geom
FROM planet_osm_polygon
WHERE amenity NOT IN ('hospital', 'clinic') OR amenity IS null;

--select all roads where the grade is above a footway, i.e., passable by car
CREATE TABLE passableroads AS
(SELECT *, st_transform(way,32737)::geometry(linestring, 32737) AS geom
FROM planet_osm_line
WHERE highway IS NOT null
AND NOT highway = 'path'
AND NOT highway ='footway');

--remove interfering geometry
ALTER TABLE passableroads
DROP COLUMN way;

--calculate the distance between each building and the nearest passable road
SELECT buildingcentroids.*, st_distance(a.roadgeom, buildingcentroids.geom) AS roadaccess
FROM buildingcentroids CROSS JOIN lateral (
	SELECT passableroads.osm_id AS roadid, passableroads.geom AS roadgeom
	FROM passableroads
	ORDER BY passableroads.geom <-> buildingcentroids.geom
	LIMIT 1) a;



--select hospitals and clinics from all buildings
CREATE TABLE hospitalpolygons AS
SELECT *
FROM planet_osm_polygon
WHERE amenity = 'hospital'
OR amenity = 'clinic';

--create centroi layer for hospitals and clinics
CREATE TABLE hospitalcentroids AS
SELECT *, st_transform(st_centroid(way),32737)::geometry(point,32737) AS geom
FROM hospitalpolygons;

--remove interfering geometries
ALTER TABLE hospitalcentroids
DROP COLUMN way;


--prep buildingentroids to recieve ward data
ALTER TABLE buildingcentroids
ADD COLUMN ward varchar;

--reproject wards
CREATE TABLE wardsreproject AS
SELECT *, st_transform(wards.geom,32737)::geometry(multipolygon,32737) AS geomw
FROM wards;

--remove interfering geometries
ALTER TABLE wardsreproject
DROP COLUMN geom;

--apply ward information to buildings layer
UPDATE buildingcentroids
SET ward = ward_name
FROM wardsreproject
WHERE st_intersects(buildingcentroids.geom, wardsreproject.geomw);

--calculate distance between building centroids and hospital centroids THIS CALCULATES DISTANCE BETWEEN A BUILDING AND ALL HOSPITAL POINTS, NOT THE BUILDING AND NEAREST HOSPITAL
CREATE TABLE hospitalaccess AS
SELECT buildingcentroids.*, st_distance(a.hospitalgeom, buildingcentroids.geom) AS hospitalaccess
FROM buildingcentroids CROSS JOIN lateral (
SELECT hospitalcentroids.osm_id AS hospitalid, hospitalcentroids.geom AS hospitalgeom
FROM hospitalcentroids
ORDER BY hospitalcentroids.geom <-> buildingcentroids.geom
LIMIT 1) a;

--join tables to get both road access and hospital access information
CREATE TABLE ambulanceaccess AS
SELECT hospitalaccess.*, buildingroadaccess.roadaccess AS roadaccess
FROM hospitalaccess LEFT JOIN buildingroadaccess
ON hospitalaccess.osm_id = buildingroadaccess.osm_id;

--summarize data by ward
CREATE TABLE wardsummary AS
SELECT ward, avg(hospitalaccess) AS avghospitaldist, avg(roadaccess) AS avgroadaccess, count(osm_id) AS count
FROM ambulanceaccess
GROUP BY ward;
