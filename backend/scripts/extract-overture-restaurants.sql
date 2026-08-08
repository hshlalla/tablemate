-- 실행: duckdb < backend/scripts/extract-overture-restaurants.sql
-- Overture Maps release 버전은 https://overturemaps.org/release 에서 최신 값으로 갱신 필요
-- 출력 데이터는 CDLA Permissive v2.0 라이선스 — 앱 내 attribution 표기 필요 (Task 11 참고)

INSTALL spatial;
INSTALL httpfs;
LOAD spatial;
LOAD httpfs;
SET s3_region='us-west-2';

COPY (
    SELECT
        id AS overture_id,
        names.primary AS name,
        categories.primary AS category,
        ST_Y(geometry) AS latitude,
        ST_X(geometry) AS longitude,
        addresses[1].freeform AS address
    FROM read_parquet(
        's3://overturemaps-us-west-2/release/2026-06-25.0/theme=places/type=place/*',
        filename=true,
        hive_partitioning=1
    )
    WHERE categories.primary IN ('restaurant', 'cafe', 'fast_food', 'bar', 'food_court')
      AND ST_Y(geometry) BETWEEN 37.40 AND 37.70
      AND ST_X(geometry) BETWEEN 126.76 AND 127.18
) TO 'backend/scripts/output/seoul-restaurants.csv' (HEADER, DELIMITER ',');
