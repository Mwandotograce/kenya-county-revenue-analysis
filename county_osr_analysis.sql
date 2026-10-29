-- =====================================================
-- KENYA COUNTY OWN-SOURCE REVENUE (OSR) ANALYSIS
-- Financial Years: 2022/23, 2023/24, 2024/25, 2025/26
-- Tool: MySQL
-- =====================================================


-- =====================================================
-- 1. DATABASE SETUP AND DATA LOADING
-- =====================================================

CREATE DATABASE IF NOT EXISTS kenya_county_revenue
CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

USE kenya_county_revenue;

DROP TABLE IF EXISTS county_osr;
CREATE TABLE county_osr (
    financial_year     VARCHAR(10),
    county             VARCHAR(50),
    revenue_target_mn  DECIMAL(12,2),
    actual_revenue_mn  DECIMAL(12,2)
);

-- Load the cleaned county OSR CSV file.
-- Figures are stored in KSh millions.
LOAD DATA LOCAL INFILE 'C:/Users/ADMIN/Desktop/PROJECTS/county_ors/county_osr.csv'
INTO TABLE county_osr
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 LINES
(@fy, @county, @target, @actual)
SET
    financial_year    = TRIM(@fy),
    county            = TRIM(@county),
    revenue_target_mn = CAST(REPLACE(TRIM(@target), ',', '') AS DECIMAL(12,2)),
    actual_revenue_mn = CAST(REPLACE(TRIM(@actual), ',', '') AS DECIMAL(12,2));
    

-- =====================================================
-- 2. DATA VALIDATION CHECKS
-- =====================================================

-- Check total records. Expected: 188 rows (47 counties x 4 financial years).
SELECT COUNT(*) AS total_rows FROM county_osr;

-- Check that each financial year has 47 counties.
SELECT financial_year, COUNT(*) AS counties
FROM county_osr
GROUP BY financial_year
ORDER BY financial_year;

-- Check for missing or invalid numeric values.
SELECT
    SUM(revenue_target_mn IS NULL) AS null_targets,
    SUM(actual_revenue_mn IS NULL) AS null_actuals,
    SUM(revenue_target_mn = 0)     AS zero_targets
FROM county_osr;

-- Check that the dataset contains all 47 counties.
SELECT COUNT(DISTINCT county) AS distinct_counties FROM county_osr;


-- =====================================================
-- 3. NATIONAL OSR PERFORMANCE
-- =====================================================

-- Qn 1: What was total OSR collected vs target each year?
-- Calculates national target, actual OSR, and collection rate by financial year.
SELECT 
    financial_year, 
    ROUND(SUM(revenue_target_mn), 2) AS target_mn,
    ROUND(SUM(actual_revenue_mn), 2) AS actual_mn,
    ROUND(SUM(actual_revenue_mn) / SUM(revenue_target_mn) * 100, 1) AS collection_rate_pct
FROM county_osr
GROUP BY financial_year
ORDER BY financial_year;

-- Qn 2: What was the national revenue gap each year?
-- Revenue gap = target OSR - actual OSR.
SELECT financial_year, 
SUM(revenue_target_mn) - SUM(actual_revenue_mn) AS revenue_gap
FROM county_osr
GROUP BY financial_year
ORDER BY financial_year;


-- =====================================================
-- 4. REVENUE CONCENTRATION
-- =====================================================

-- Qn 3: What share of national OSR does each county contribute?
-- This example shows the top 5 counties by actual OSR in FY 2025/26.
SELECT
    financial_year,
    county,
    actual_revenue_mn,
    SUM(actual_revenue_mn) OVER (PARTITION BY financial_year) AS national_actual,
    ROUND(
        actual_revenue_mn /
        SUM(actual_revenue_mn) OVER (PARTITION BY financial_year) * 100,
        1
    ) AS share_of_national_osr_pct
FROM county_osr
WHERE financial_year = '25/26'
ORDER BY actual_revenue_mn DESC
LIMIT 5;

-- Qn 4: How concentrated is OSR among the top 5 counties each year?
-- Uses RANK() to identify the top 5 counties per financial year.
WITH ranked AS (
    SELECT
        financial_year,
        county,
        actual_revenue_mn,
        RANK() OVER (
            PARTITION BY financial_year
            ORDER BY actual_revenue_mn DESC
        ) AS county_rank,
        SUM(actual_revenue_mn) OVER (
            PARTITION BY financial_year
        ) AS national_actual
    FROM county_osr
)
SELECT
    financial_year,
    ROUND(
        SUM(CASE WHEN county_rank <= 5 THEN actual_revenue_mn ELSE 0 END)
        / MAX(national_actual) * 100,
        1
    ) AS top5_share_pct
FROM ranked
GROUP BY financial_year
ORDER BY financial_year;


-- =====================================================
-- 5. COUNTY PERFORMANCE RANKINGS
-- =====================================================

-- Qn 5: Which counties collected the most OSR in absolute terms?
-- Ranks counties by total actual OSR collected across all four years.
SELECT
    county,
    ROUND(SUM(actual_revenue_mn), 2) AS total_actual_osr_mn,
    ROUND(SUM(revenue_target_mn), 2) AS total_target_mn,
    ROUND(SUM(actual_revenue_mn) / SUM(revenue_target_mn) * 100, 1) AS collection_rate_pct
FROM county_osr
GROUP BY county
ORDER BY total_actual_osr_mn DESC;

-- Qn 6: Which counties had the highest cumulative collection rates?
-- Collection rate = total actual OSR / total target OSR.
SELECT
    county,
    ROUND(SUM(actual_revenue_mn), 2) AS total_actual_osr_mn,
    ROUND(SUM(revenue_target_mn), 2) AS total_target_mn,
    ROUND(SUM(actual_revenue_mn) / SUM(revenue_target_mn) * 100, 1) AS collection_rate_pct
FROM county_osr
GROUP BY county
ORDER BY collection_rate_pct DESC
LIMIT 10;


-- =====================================================
-- 6. TARGET ACHIEVEMENT CONSISTENCY
-- =====================================================

-- Qn 7: Which counties met or exceeded their annual targets, and how often?
-- years_target_met counts the number of years where actual OSR >= target OSR.
SELECT
    county,
    COUNT(*) AS years_available,
    SUM(CASE WHEN actual_revenue_mn >= revenue_target_mn THEN 1 ELSE 0 END) AS years_target_met
FROM county_osr
GROUP BY county
HAVING years_target_met >= 1
ORDER BY years_target_met DESC, county;


-- =====================================================
-- 7. CHRONIC UNDERPERFORMANCE
-- =====================================================

-- Qn 8: Which counties were chronic underperformers?
-- Identifies counties that collected below 50% of target in at least 2 of the 4 years.
SELECT
    county,
    SUM(CASE WHEN (actual_revenue_mn / NULLIF(revenue_target_mn, 0)) < 0.50 THEN 1 ELSE 0 END) AS years_below_50_pct,
    COUNT(*) AS total_years,
    ROUND(SUM(actual_revenue_mn), 2) AS total_actual_mn,
    ROUND(SUM(revenue_target_mn), 2) AS total_target_mn,
    ROUND(SUM(actual_revenue_mn) / NULLIF(SUM(revenue_target_mn), 0) * 100, 1) AS cumulative_collection_rate_pct,
    ROUND(SUM(revenue_target_mn) - SUM(actual_revenue_mn), 2) AS cumulative_gap_mn
FROM county_osr
GROUP BY county
HAVING years_below_50_pct >= 2
ORDER BY years_below_50_pct DESC, cumulative_collection_rate_pct ASC;

-- Drill-down: annual collection rates for Siaya and Kisumu.
-- These counties appeared as chronic underperformers.
SELECT 
    county,
    financial_year,
    revenue_target_mn,
    actual_revenue_mn,
    ROUND((actual_revenue_mn / revenue_target_mn) * 100, 1) AS collection_rate_pct
FROM county_osr
WHERE county IN ('Siaya', 'Kisumu')
ORDER BY county, financial_year;


-- =====================================================
-- 8. FIRST YEAR VS LAST YEAR PERFORMANCE
-- =====================================================

-- Qn 9: Which counties improved the most between FY 2022/23 and FY 2025/26?
-- This compares the first and last year side by side using two CTEs.

-- List 1: First year (22/23)
WITH year_22 AS (
    SELECT 
        county, 
        actual_revenue_mn AS actual_22, 
        revenue_target_mn AS target_22,
        (actual_revenue_mn / revenue_target_mn) * 100 AS rate_22
    FROM county_osr
    WHERE financial_year = '22/23'
),

-- List 2: Last year (25/26)
year_25 AS (
    SELECT 
        county, 
        actual_revenue_mn AS actual_25, 
        revenue_target_mn AS target_25,
        (actual_revenue_mn / revenue_target_mn) * 100 AS rate_25
    FROM county_osr
    WHERE financial_year = '25/26'
)

-- Put them side by side and subtract!
-- This version returns the top 5 counties by improvement in collection rate.
SELECT 
    year_25.county,
    ROUND(year_22.rate_22, 1) AS rate_22_23_pct,
    ROUND(year_25.rate_25, 1) AS rate_25_26_pct,
    ROUND(year_25.rate_25 - year_22.rate_22, 1) AS rate_change_pp,
    ROUND(year_25.actual_25 - year_22.actual_22, 2) AS shilling_growth_mn,
    ROUND(((year_25.actual_25 - year_22.actual_22) / year_22.actual_22) * 100, 1) AS revenue_growth_pct
FROM year_25
JOIN year_22 ON year_25.county = year_22.county
ORDER BY rate_change_pp DESC
LIMIT 5;

-- Qn 9 continued: Which counties declined the most in collection rate?
-- Uses the same first-year vs last-year comparison, sorted in ascending order.
WITH year_22 AS (
    SELECT 
        county, 
        actual_revenue_mn AS actual_22, 
        revenue_target_mn AS target_22,
        (actual_revenue_mn / revenue_target_mn) * 100 AS rate_22
    FROM county_osr
    WHERE financial_year = '22/23'
),
year_25 AS (
    SELECT 
        county, 
        actual_revenue_mn AS actual_25, 
        revenue_target_mn AS target_25,
        (actual_revenue_mn / revenue_target_mn) * 100 AS rate_25
    FROM county_osr
    WHERE financial_year = '25/26'
)
SELECT 
    year_25.county,
    ROUND(year_22.rate_22, 1) AS rate_22_23_pct,
    ROUND(year_25.rate_25, 1) AS rate_25_26_pct,
    ROUND(year_25.rate_25 - year_22.rate_22, 1) AS rate_change_pp,
    ROUND(year_25.actual_25 - year_22.actual_22, 2) AS shilling_growth_mn,
    ROUND(((year_25.actual_25 - year_22.actual_22) / year_22.actual_22) * 100, 1) AS revenue_growth_pct
FROM year_25
JOIN year_22 ON year_25.county = year_22.county
ORDER BY rate_change_pp ASC
LIMIT 5;


-- =====================================================
-- 9. TARGET REALISM AND AMBITION GAP
-- =====================================================

-- Qn 10: Did targets grow faster than actual collections?
-- Ambition Gap = Target Growth % - Actual Collection Growth %
-- Positive gap: targets grew faster than actual collections.
-- Negative gap: actual collections grew faster than targets.
WITH year_22 AS (
    SELECT county,
           actual_revenue_mn AS actual_22,
           revenue_target_mn AS target_22
    FROM county_osr
    WHERE financial_year = '22/23'
),
year_25 AS (
    SELECT county,
           actual_revenue_mn AS actual_25,
           revenue_target_mn AS target_25
    FROM county_osr
    WHERE financial_year = '25/26'
)
SELECT
    y25.county,
    ROUND((y25.target_25 - y22.target_22) / y22.target_22 * 100, 1) AS target_growth_pct,
    ROUND((y25.actual_25 - y22.actual_22) / y22.actual_22 * 100, 1) AS actual_growth_pct,
    ROUND(
        ((y25.target_25 - y22.target_22) / y22.target_22 * 100)
      - ((y25.actual_25 - y22.actual_22) / y22.actual_22 * 100)
    , 1) AS ambition_gap_pp
FROM year_25 y25
JOIN year_22 y22 ON y25.county = y22.county
ORDER BY ambition_gap_pp desc;


-- =====================================================
-- 10. NATIONAL BENCHMARK OPPORTUNITY
-- =====================================================

-- Qn 11: If below-average counties reached the national average collection rate,
-- how much additional revenue would have been collected?
-- 0.7825 represents the 4-year national collection rate:
-- total actual OSR / total revenue target = 78.25%.
SELECT 
    county,
    ROUND(SUM(revenue_target_mn), 2) AS total_target_mn,
    ROUND(SUM(actual_revenue_mn), 2) AS total_actual_mn,
    ROUND(SUM(actual_revenue_mn) / SUM(revenue_target_mn) * 100, 1) AS current_rate_pct,
    ROUND(SUM(revenue_target_mn) * 0.7825, 2) AS revenue_at_nat_avg_mn, -- 0.7825 represents the 4-year national collection rate: total actual OSR / total revenue target = 78.25%
    ROUND((SUM(revenue_target_mn) * 0.7825) - SUM(actual_revenue_mn), 2) AS extra_revenue_mn
FROM county_osr
GROUP BY county
HAVING current_rate_pct < 78.25
ORDER BY extra_revenue_mn DESC;

-- Summary of the national benchmark opportunity.
-- Counts below-average counties and sums the additional revenue opportunity.
WITH below_average_counties AS (
    SELECT 
        county,
        SUM(revenue_target_mn) AS total_target,
        SUM(actual_revenue_mn) AS total_actual
    FROM county_osr
    GROUP BY county
    HAVING (SUM(actual_revenue_mn) / SUM(revenue_target_mn)) < 0.78252
)
SELECT 
    COUNT(*) AS counties_below_national_avg,
    ROUND(SUM((total_target * 0.78252) - total_actual), 2) AS total_additional_revenue_mn
FROM below_average_counties;


-- =====================================================
-- 11. REVENUE GAP PRIORITISATION
-- =====================================================

-- Qn 12: Which counties have the largest total revenue gaps?
-- Also estimates the value of closing 50% of each county's gap.
SELECT 
    county,
    ROUND(SUM(revenue_target_mn), 2) AS total_target_mn,
    ROUND(SUM(actual_revenue_mn), 2) AS total_actual_mn,
    ROUND(SUM(actual_revenue_mn) / SUM(revenue_target_mn) * 100, 1) AS collection_rate_pct,
    ROUND(SUM(revenue_target_mn) - SUM(actual_revenue_mn), 2) AS total_gap_mn,
    ROUND((SUM(revenue_target_mn) - SUM(actual_revenue_mn)) * 0.50, 2) AS half_gap_recovery_mn
FROM county_osr
GROUP BY county
HAVING total_gap_mn > 0
ORDER BY total_gap_mn DESC
limit 10;