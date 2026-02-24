-- ============================================================
-- NYC Taxi SQL Queries
-- Run these in pgAdmin or pgcli after ingesting data.
-- Assumes tables: yellow_taxi_trips, zones
-- ============================================================


-- ============================================================
-- Section 1: Inner Joins
-- ============================================================

-- Implicit INNER JOIN
-- Join Yellow Taxi trips with Zones lookup table using the old comma-join syntax
SELECT
    tpep_pickup_datetime,
    tpep_dropoff_datetime,
    total_amount,
    CONCAT(zpu."Borough", ' | ', zpu."Zone") AS "pickup_loc",
    CONCAT(zdo."Borough", ' | ', zdo."Zone") AS "dropoff_loc"
FROM
    yellow_taxi_trips t,
    zones zpu,
    zones zdo
WHERE
    t."PULocationID" = zpu."LocationID"
    AND t."DOLocationID" = zdo."LocationID"
LIMIT 100;


-- Explicit INNER JOIN
-- Same result as above but using explicit JOIN syntax (preferred for readability)
-- PostgreSQL treats bare JOIN as INNER JOIN by default
SELECT
    tpep_pickup_datetime,
    tpep_dropoff_datetime,
    total_amount,
    CONCAT(zpu."Borough", ' | ', zpu."Zone") AS "pickup_loc",
    CONCAT(zdo."Borough", ' | ', zdo."Zone") AS "dropoff_loc"
FROM
    yellow_taxi_trips t
JOIN -- equivalent to INNER JOIN
    zones zpu ON t."PULocationID" = zpu."LocationID"
JOIN
    zones zdo ON t."DOLocationID" = zdo."LocationID"
LIMIT 100;


-- ============================================================
-- Section 2: Data Quality Checks
-- ============================================================

-- Check for NULL Location IDs
-- Rows where pickup or dropoff location is missing
SELECT
    tpep_pickup_datetime,
    tpep_dropoff_datetime,
    total_amount,
    "PULocationID",
    "DOLocationID"
FROM
    yellow_taxi_trips
WHERE
    "PULocationID" IS NULL
    OR "DOLocationID" IS NULL
LIMIT 100;


-- Check for Location IDs NOT present in the Zones table
-- Helps identify orphaned foreign keys / data quality issues
SELECT
    tpep_pickup_datetime,
    tpep_dropoff_datetime,
    total_amount,
    "PULocationID",
    "DOLocationID"
FROM
    yellow_taxi_trips
WHERE
    "DOLocationID" NOT IN (SELECT "LocationID" FROM zones)
    OR "PULocationID" NOT IN (SELECT "LocationID" FROM zones)
LIMIT 100;


-- ============================================================
-- Section 3: LEFT, RIGHT, and OUTER JOINs
-- ============================================================

-- Setup: Delete a zone to simulate missing lookup data
-- WARNING: This modifies the zones table — used only for demonstrating outer joins
DELETE FROM zones WHERE "LocationID" = 142;


-- LEFT JOIN
-- Returns all trips; pickup zone shows NULL if LocationID 142 is missing from zones
SELECT
    tpep_pickup_datetime,
    tpep_dropoff_datetime,
    total_amount,
    CONCAT(zpu."Borough", ' | ', zpu."Zone") AS "pickup_loc",
    CONCAT(zdo."Borough", ' | ', zdo."Zone") AS "dropoff_loc"
FROM
    yellow_taxi_trips t
LEFT JOIN
    zones zpu ON t."PULocationID" = zpu."LocationID"
JOIN
    zones zdo ON t."DOLocationID" = zdo."LocationID"
LIMIT 100;


-- RIGHT JOIN
-- Returns all zones on the right side; trips without a matching pickup zone show NULL
SELECT
    tpep_pickup_datetime,
    tpep_dropoff_datetime,
    total_amount,
    CONCAT(zpu."Borough", ' | ', zpu."Zone") AS "pickup_loc",
    CONCAT(zdo."Borough", ' | ', zdo."Zone") AS "dropoff_loc"
FROM
    yellow_taxi_trips t
RIGHT JOIN
    zones zpu ON t."PULocationID" = zpu."LocationID"
JOIN
    zones zdo ON t."DOLocationID" = zdo."LocationID"
LIMIT 100;


-- OUTER JOIN (FULL OUTER JOIN)
-- Returns all rows from both sides, filling NULLs where there is no match
SELECT
    tpep_pickup_datetime,
    tpep_dropoff_datetime,
    total_amount,
    CONCAT(zpu."Borough", ' | ', zpu."Zone") AS "pickup_loc",
    CONCAT(zdo."Borough", ' | ', zdo."Zone") AS "dropoff_loc"
FROM
    yellow_taxi_trips t
FULL OUTER JOIN
    zones zpu ON t."PULocationID" = zpu."LocationID"
JOIN
    zones zdo ON t."DOLocationID" = zdo."LocationID"
LIMIT 100;


-- ============================================================
-- Section 4: GROUP BY
-- ============================================================

-- Count trips per day
-- CAST datetime to DATE to group by calendar day
SELECT
    CAST(tpep_dropoff_datetime AS DATE) AS "day",
    COUNT(1)
FROM
    yellow_taxi_trips
GROUP BY
    CAST(tpep_dropoff_datetime AS DATE)
LIMIT 100;


-- ============================================================
-- Section 5: ORDER BY
-- ============================================================

-- Order by day (ascending)
SELECT
    CAST(tpep_dropoff_datetime AS DATE) AS "day",
    COUNT(1)
FROM
    yellow_taxi_trips
GROUP BY
    CAST(tpep_dropoff_datetime AS DATE)
ORDER BY
    "day" ASC
LIMIT 100;


-- Order by trip count (descending) — shows the busiest days first
SELECT
    CAST(tpep_dropoff_datetime AS DATE) AS "day",
    COUNT(1) AS "count"
FROM
    yellow_taxi_trips
GROUP BY
    CAST(tpep_dropoff_datetime AS DATE)
ORDER BY
    "count" DESC
LIMIT 100;


-- ============================================================
-- Section 6: Other Aggregations
-- ============================================================

-- Per-day stats: trip count, max fare, max passenger count
SELECT
    CAST(tpep_dropoff_datetime AS DATE) AS "day",
    COUNT(1) AS "count",
    MAX(total_amount) AS "total_amount",
    MAX(passenger_count) AS "passenger_count"
FROM
    yellow_taxi_trips
GROUP BY
    CAST(tpep_dropoff_datetime AS DATE)
ORDER BY
    "count" DESC
LIMIT 100;


-- ============================================================
-- Section 7: GROUP BY Multiple Fields
-- ============================================================

-- Group by day AND dropoff location ID (using positional references 1, 2)
-- Positional GROUP BY: 1 = first SELECT column, 2 = second SELECT column
SELECT
    CAST(tpep_dropoff_datetime AS DATE) AS "day",
    "DOLocationID",
    COUNT(1) AS "count",
    MAX(total_amount) AS "total_amount",
    MAX(passenger_count) AS "passenger_count"
FROM
    yellow_taxi_trips
GROUP BY
    1, 2
ORDER BY
    "day" ASC,
    "DOLocationID" ASC
LIMIT 100;

