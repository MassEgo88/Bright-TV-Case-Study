---1.Check the raw viewer table

SELECT * 
FROM tv_viewer 
LIMIT 10; 

DESCRIBE tv_viewer;

---2.Check the raw profile table

SELECT * 
FROM tv_profile LIMIT 10; 

DESCRIBE tv_profile;

----------------------------------------------------------------------------------------------------------------------
---3.Clean the viewer table 
----------------------------------------------------------------------------------------------------------------------

CREATE OR REPLACE TABLE tv_viewer_clean AS SELECT
CAST(COALESCE(`userid`, UserID) AS BIGINT) AS UserID,
CAST(UserID AS BIGINT) AS UserID_original, CAST(`userid` AS BIGINT) AS userid_lowercase, CASE
WHEN CAST(UserID AS BIGINT) = CAST(`userid` AS BIGINT) THEN 'Match'
ELSE 'Mismatch' END AS ID_Match_Flag,

TRIM(Channel2) AS Channel,

TO_TIMESTAMP(RecordDate2, 'dd/MM/yyyy HH:mm') AS RecordDate_UTC, FROM_UTC_TIMESTAMP(
TO_TIMESTAMP(RecordDate2, 'dd/MM/yyyy HH:mm'), 'Africa/Johannesburg'
) AS RecordDate_CAT,

TO_DATE(
FROM_UTC_TIMESTAMP(
TO_TIMESTAMP(RecordDate2, 'dd/MM/yyyy HH:mm'), 'Africa/Johannesburg'
)
) AS View_Date,

DATE_FORMAT(
FROM_UTC_TIMESTAMP(
TO_TIMESTAMP(RecordDate2, 'dd/MM/yyyy HH:mm'), 'Africa/Johannesburg'
),
'HH:mm:ss'
) AS View_Time,

CAST(SPLIT(`Duration 2`, ':')[0] AS INT) * 3600 + CAST(SPLIT(`Duration 2`, ':')[1] AS INT) * 60 +
CAST(SPLIT(`Duration 2`, ':')[2] AS INT) AS Duration_Seconds,

ROUND((
CAST(SPLIT(`Duration 2`, ':')[0] AS INT) * 3600 + CAST(SPLIT(`Duration 2`, ':')[1] AS INT) * 60 + CAST(SPLIT(`Duration 2`, ':')[2] AS INT)
) / 60.0, 2) AS Duration_Minutes FROM tv_viewer;
4.Remove bad viewer rows for analysis
CREATE OR REPLACE TABLE tv_viewer_analysis_ready AS SELECT *
FROM tv_viewer_clean WHERE Channel IS NOT NULL
AND RecordDate_CAT IS NOT NULL AND Duration_Seconds > 0;

---------------------------------------------------------------------------------------------------------------------------------
----5.Clean the profile table 
---------------------------------------------------------------------------------------------------------------------------------

CREATE OR REPLACE TABLE tv_profile_clean AS SELECT
CAST(UserID AS BIGINT) AS UserID,
NULLIF(TRIM(regexp_replace(Name, '[\u00A0]', ' ')), '') AS Name, NULLIF(TRIM(regexp_replace(Surname, '[\u00A0]', ' ')), '') AS Surname, LOWER(NULLIF(TRIM(regexp_replace(Email, '[\u00A0]', ' ')), '')) AS Email, INITCAP(NULLIF(TRIM(Gender), '')) AS Gender,
INITCAP(NULLIF(TRIM(Race), '')) AS Race, CAST(Age AS INT) AS Age,

CASE
   WHEN LOWER(TRIM(Province)) = 'kwazulu natal' THEN 'KwaZulu-Natal' 
   WHEN LOWER(TRIM(Province)) = 'north west' THEN 'North West'
   WHEN LOWER(TRIM(Province)) = 'free state' THEN 'Free State' 
   WHEN LOWER(TRIM(Province)) = 'eastern cape' THEN 'Eastern Cape' 
   WHEN LOWER(TRIM(Province)) = 'western cape' THEN 'Western Cape'
   WHEN LOWER(TRIM(Province)) = 'northern cape' THEN 'Northern Cape' 
   WHEN LOWER(TRIM(Province)) = 'mpumalanga' THEN 'Mpumalanga'
   WHEN LOWER(TRIM(Province)) = 'limpopo' THEN 'Limpopo' 
   WHEN LOWER(TRIM(Province)) = 'gauteng' THEN 'Gauteng' 
  ELSE NULLIF(TRIM(Province), '')
END AS Province,
NULLIF(TRIM(regexp_replace(`Social Media Handle`, '[\u00A0]', ' ')), '') AS Social_Media_Handle, CASE
  WHEN Age BETWEEN 0 AND 12 THEN 'Child' WHEN Age BETWEEN 13 AND 17 THEN 'Teen' WHEN Age BETWEEN 18 AND 24 THEN '18-24'
  WHEN Age BETWEEN 25 AND 34 THEN '25-34'
  WHEN Age BETWEEN 35 AND 44 THEN '35-44'
  WHEN Age BETWEEN 45 AND 54 THEN '45-54'
ELSE '55+'
END AS Age_Group

FROM tv_profile WHERE NOT (
CAST(Age AS INT) = 0 AND Name IS NULL
AND Surname IS NULL
);

----------------------------------------------------------------------------------------------------------------------------------
---6. LEFT Join to the clean tables
----------------------------------------------------------------------------------------------------------------------------------

CREATE OR REPLACE TABLE brighttv_analysis_long AS SELECT
v.UserID,

p.Name, 
p.Surname, 
p.Email, 
p.Gender, 
p.Race, 
p.Age, 
p.Age_Group, 
p.Province,
p.Social_Media_Handle,

v.Channel, 
v.RecordDate_UTC, 
v.RecordDate_CAT,
v.View_Date, 
v.View_Time, 
v.Duration_Seconds, 
v.Duration_Minutes, 
v.ID_Match_Flag,
DATE_FORMAT(v.View_Date, 'EEEE') AS Day_Name, 
  CASE
WHEN DATE_FORMAT(v.View_Date, 'u') IN ('6', '7') THEN 'Weekend'
ELSE 'Weekday' 
  END AS Day_Type,

CASE
   WHEN HOUR(v.RecordDate_CAT) BETWEEN 5 AND 11 THEN 'Morning' 
   WHEN HOUR(v.RecordDate_CAT) BETWEEN 12 AND 16 THEN 'Afternoon' 
   WHEN HOUR(v.RecordDate_CAT) BETWEEN 17 AND 21 THEN 'Evening' 
  ELSE 'Late Night'
END AS Time_Period

FROM tv_viewer_analysis_ready v 
LEFT JOIN tv_profile_clean p
ON v.UserID = p.UserID;

---------------------------------------------------------------------------------------------------------------------------------------------------
---7.Final table with no important nulls
----------------------------------------------------------------------------------------------------------------------------------------------------

CREATE OR REPLACE TABLE brighttv_analysis_clean AS 
SELECT *
FROM brighttv_analysis_long 
WHERE UserID IS NOT NULL
AND Channel IS NOT NULL AND View_Date IS NOT NULL
AND Duration_Minutes IS NOT NULL AND Province IS NOT NULL
AND Gender IS NOT NULL
AND Race IS NOT NULL 
AND Email IS NOT NULL;

---8.Quick checks after cleaning

SELECT COUNT(*) AS viewer_rows 
FROM tv_viewer_clean; 

SELECT COUNT(*) AS profile_rows 
FROM tv_profile_clean;

SELECT COUNT(*) AS final_rows 
FROM brighttv_analysis_clean;

SELECT ID_Match_Flag, COUNT(*) AS rows 
FROM tv_viewer_clean
GROUP BY ID_Match_Flag;

SELECT COUNT(*) AS zero_duration_rows 
FROM tv_viewer_clean
WHERE Duration_Seconds = 0;

--------------------------------------------------------------------------------------------------------------------
----9.Example analysis queries in DESC order
---------------------------------------------------------------------------------------------------------------------

SELECT
Day_Name,
COUNT(*) AS Sessions,
ROUND(SUM(Duration_Minutes) / 60, 2) AS Total_Hours 
FROM brighttv_analysis_clean
GROUP BY Day_Name
ORDER BY Total_Hours DESC;

SELECT
Channel,
ROUND(SUM(Duration_Minutes) / 60, 2) AS Total_Hours 
FROM brighttv_analysis_clean
GROUP BY Channel
ORDER BY Total_Hours DESC;

SELECT
Age_Group, COUNT(*) AS Views
FROM brighttv_analysis_clean GROUP BY Age_Group
ORDER BY Views DESC;
