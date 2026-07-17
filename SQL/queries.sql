-- ============================================================
-- ЗАПРОС 1: Общая сегментация рынка ЮАР по цене и качеству
-- ============================================================
WITH variety_stats AS (
    SELECT variety,
           AVG(price) AS avg_price,
           AVG(points) AS avg_points
    FROM wine_data
    WHERE country = 'South Africa' AND price IS NOT NULL
    GROUP BY variety
),
market_median AS (
    SELECT 
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY avg_price) AS median_price,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY avg_points) AS median_points
    FROM variety_stats
),
variety_segments AS (
    SELECT variety,
           avg_price,
           avg_points,
           CASE 
               WHEN avg_price >= (SELECT median_price FROM market_median) 
                    AND avg_points >= (SELECT median_points FROM market_median) THEN 'Premium'
               WHEN avg_price < (SELECT median_price FROM market_median) 
                    AND avg_points >= (SELECT median_points FROM market_median) THEN 'Value'
               WHEN avg_price < (SELECT median_price FROM market_median) 
                    AND avg_points < (SELECT median_points FROM market_median) THEN 'Economy'
               ELSE 'Overpriced'
           END AS segment
    FROM variety_stats
)
SELECT 
    segment,
    COUNT(variety) AS variety_count,
    ROUND(MIN(avg_price)::numeric, 2) AS price_min,
    ROUND(PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY avg_price)::numeric, 2) AS price_p25,
    ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY avg_price)::numeric, 2) AS price_median,
    ROUND(PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY avg_price)::numeric, 2) AS price_p75,
    ROUND(MAX(avg_price)::numeric, 2) AS price_max,
    ROUND(MIN(avg_points)::numeric, 2) AS points_min,
    ROUND(PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY avg_points)::numeric, 2) AS points_p25,
    ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY avg_points)::numeric, 2) AS points_median,
    ROUND(PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY avg_points)::numeric, 2) AS points_p75,
    ROUND(MAX(avg_points)::numeric, 2) AS points_max
FROM variety_segments
GROUP BY segment
ORDER BY segment;

-- ============================================================
-- ЗАПРОС 2: Сорта в Premium и Overpriced с долей рынка
-- ============================================================
WITH variety_stats AS (
    SELECT variety,
           AVG(price) AS avg_price,
           AVG(points) AS avg_points,
           COUNT(*) AS wine_count
    FROM wine_data
    WHERE country = 'South Africa' AND price IS NOT NULL
    GROUP BY variety
    HAVING COUNT(*) >= 3
),
market_median AS (
    SELECT 
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY avg_price) AS median_price,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY avg_points) AS median_points
    FROM variety_stats
),
segmented AS (
    SELECT variety,
           avg_price,
           avg_points,
           wine_count,
           CASE 
               WHEN avg_price >= (SELECT median_price FROM market_median) 
                    AND avg_points >= (SELECT median_points FROM market_median) THEN 'Premium'
               WHEN avg_price >= (SELECT median_price FROM market_median) 
                    AND avg_points < (SELECT median_points FROM market_median) THEN 'Overpriced'
           END AS segment
    FROM variety_stats
)
SELECT 
    variety,
    wine_count,
    ROUND(wine_count * 100.0 / SUM(wine_count) OVER(), 2) AS share_percent
FROM segmented
WHERE segment IN ('Premium', 'Overpriced')
ORDER BY wine_count DESC, variety;

-- ============================================================
-- ЗАПРОС 3: Средний размер портфеля винодельни
-- ============================================================
SELECT ROUND(AVG(wine_count), 1) AS avg_portfolio_size
FROM (
    SELECT winery, COUNT(*) AS wine_count
    FROM wine_data
    WHERE country = 'South Africa' AND price IS NOT NULL
    GROUP BY winery
) t;

-- ============================================================
-- ЗАПРОС 4: Отклонение сортов от диагонали (Premium / Overpriced)
-- ============================================================
WITH variety_stats AS (
    SELECT variety,
           AVG(price) AS avg_price,
           AVG(points) AS avg_points
    FROM wine_data
    WHERE country = 'South Africa' AND price IS NOT NULL
    GROUP BY variety
    HAVING COUNT(*) >= 3
),
market_median AS (
    SELECT 
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY avg_price) AS median_price,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY avg_points) AS median_points
    FROM variety_stats
),
regression AS (
    SELECT 
        REGR_SLOPE(avg_points, avg_price) AS slope,
        REGR_INTERCEPT(avg_points, avg_price) AS intercept
    FROM variety_stats
)
SELECT 
    CASE 
        WHEN avg_price >= (SELECT median_price FROM market_median) 
             AND avg_points >= (SELECT median_points FROM market_median) THEN 'Premium'
        WHEN avg_price >= (SELECT median_price FROM market_median) 
             AND avg_points < (SELECT median_points FROM market_median) THEN 'Overpriced'
    END AS segment,
    variety,
    ROUND(avg_price::numeric, 1) AS avg_price,
    ROUND(avg_points::numeric, 1) AS avg_points,
    ROUND((avg_points - ((SELECT slope FROM regression) * avg_price + (SELECT intercept FROM regression)))::numeric, 2) AS deviation
FROM variety_stats
WHERE 
    (avg_price >= (SELECT median_price FROM market_median) 
     AND avg_points >= (SELECT median_points FROM market_median))
    OR 
    (avg_price >= (SELECT median_price FROM market_median) 
     AND avg_points < (SELECT median_points FROM market_median))
ORDER BY segment, avg_price, avg_points DESC;

-- ============================================================
-- ЗАПРОС 5: Финальный отбор сортов (Premium / Overpriced)
-- ============================================================
WITH variety_stats AS (
    SELECT variety,
           AVG(price) AS avg_price,
           AVG(points) AS avg_points,
           COUNT(DISTINCT winery) AS winery_count,
           COUNT(*) AS wine_count,
           STDDEV(price) AS price_std,
           STDDEV(points) AS points_std
    FROM wine_data
    WHERE country = 'South Africa' AND price IS NOT NULL
    GROUP BY variety
    HAVING COUNT(*) >= 3
),
market_median AS (
    SELECT 
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY avg_price) AS median_price,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY avg_points) AS median_points
    FROM variety_stats
),
regression AS (
    SELECT 
        REGR_SLOPE(avg_points, avg_price) AS slope,
        REGR_INTERCEPT(avg_points, avg_price) AS intercept
    FROM variety_stats
)
SELECT 
    CASE 
        WHEN avg_price >= (SELECT median_price FROM market_median) 
             AND avg_points >= (SELECT median_points FROM market_median) THEN 'Premium'
        WHEN avg_price >= (SELECT median_price FROM market_median) 
             AND avg_points < (SELECT median_points FROM market_median) THEN 'Overpriced'
    END AS segment,
    variety,
    winery_count,
    wine_count,
    ROUND(wine_count * 100.0 / SUM(wine_count) OVER(), 2) AS market_share,
    ROUND(avg_price::numeric, 2) AS avg_price,
    ROUND(avg_points::numeric, 2) AS avg_points,
    ROUND((avg_points - ((SELECT slope FROM regression) * avg_price + (SELECT intercept FROM regression)))::numeric, 2) AS deviation,
    ROUND(price_std::numeric, 2) AS price_std,
    ROUND(points_std::numeric, 2) AS points_std
FROM variety_stats
WHERE 
    (avg_price >= (SELECT median_price FROM market_median) 
     AND avg_points >= (SELECT median_points FROM market_median))
    OR 
    (avg_price >= (SELECT median_price FROM market_median) 
     AND avg_points < (SELECT median_points FROM market_median))
ORDER BY segment, winery_count DESC, variety;