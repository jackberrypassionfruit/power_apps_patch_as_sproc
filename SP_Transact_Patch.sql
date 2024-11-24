SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE PROCEDURE [dbo].[SP_Transact_Patch] 
	@json_body nvarchar(MAX),
    @dest_table_name nvarchar(2000),
	@execute bit = 1,
	@output_query NVARCHAR(MAX) OUTPUT
AS
BEGIN

DECLARE 
	@columns_pivot			NVARCHAR(MAX), 
	@columns_for_insert		NVARCHAR(MAX),
	@columns_for_update		NVARCHAR(MAX), 
	@sql_data_query			NVARCHAR(MAX), 
	@sql_transact_query		NVARCHAR(MAX),
	@matching_pk_ids_query	NVARCHAR(MAX),
	@matching_pk_ids		INT
	--@mismatch_cols		TINYINT;


-- Clean input
SET @json_body = REPLACE(@json_body, '''', ''''''); -- turn ' into ''

SET @columns_pivot =		N'';
SET @columns_for_insert =	N'';
SET @columns_for_update =	N'';
--SET @mismatch_cols = 0;

-- Realized that the queries themselves can figure out for themselves whether or not they can succeed
-- Also, custom errors are hard
---- If trying to INSERT/UPDATE to a column not in the DCAP table, return an ERROR
--WITH json_tags AS (
--	SELECT
--		a.[key] AS row_num
--		,b.[key]
--		,b.value
--		,@dest_table_name AS table_name
--	FROM OPENJSON((@json_body)) AS a -- json_rows
--	CROSS APPLY OPENJSON(value, '$') AS b
--)

--,column_mismatch_check AS (
--	SELECT
--		a.col AS json_columns
--		,b.col as dcap_columns
--		,CASE
--			WHEN b.col IS NULL THEN 1
--			ELSE					0
--		END AS mismatches
--	FROM (
--		SELECT DISTINCT 
--			[key] COLLATE SQL_Latin1_General_CP1_CI_AS AS col
--			,table_name
--		FROM json_tags
--	) AS a
--	LEFT JOIN (
--		SELECT 
--			COLUMN_NAME AS col 
--			,TABLE_NAME
--		FROM INFORMATION_SCHEMA.COLUMNS
--		WHERE 1=1
--		AND TABLE_NAME = @dest_table_name
--		--AND COLUMN_NAME <> 'pk_id' -- This may or may not not be necessary
--	) AS b
--	ON a.col = b.col
--)

--SELECT @mismatch_cols = (SELECT SUM(mismatches) FROM column_mismatch_check);

--IF @mismatch_cols > 0
--	-- Will want to actually return a meaningful error eventually
--	SELECT @output_message = 'Dest: ['+@dest_table_name+'] - Mismatched Columns between JSON body and Destination table Schema';
	
	
-- Set column vars
WITH json_tags AS (
	SELECT
		a.[key] AS row_num
		,b.[key]
		,b.value
		,@dest_table_name AS table_name
	FROM OPENJSON((@json_body)) AS a -- json_rows
	CROSS APPLY OPENJSON(value, '$') AS b
)

SELECT @columns_pivot += N', p.' + QUOTENAME([key])
	FROM (SELECT DISTINCT [key] FROM json_tags) AS x;

SELECT @columns_for_insert = '('+STUFF(REPLACE(REPLACE(@columns_pivot, ', p.[', ', '), ']', ''), 1, 1, '')+')';

	
-- I hate the duplicating, but it's the only way to use json_tags multiple times
WITH json_tags AS (
	SELECT
		a.[key] AS row_num
		,b.[key]
		,b.value
		,@dest_table_name AS table_name
	FROM OPENJSON((@json_body)) AS a -- json_rows
	CROSS APPLY OPENJSON(value, '$') AS b
)

SELECT @columns_for_update += N', a.' + QUOTENAME([key])+' = b.'+QUOTENAME([key])
	FROM (SELECT DISTINCT [key] FROM json_tags WHERE [key] <> 'pk_id') AS x;
SELECT @columns_for_update = LTRIM(@columns_for_update, ', ')




	
SELECT @sql_data_query = N'
SELECT ' + STUFF(@columns_pivot, 1, 2, '') + '
FROM
(
	SELECT 
		row_num
		,[yek]
		-- ,[eulav]
		,CASE
			WHEN SUBSTRING([eulav], 11, 1) = ''T'' AND RIGHT([eulav], 1) = ''Z''
				THEN LEFT(CONVERT(NVARCHAR, CONVERT(DATETIME, [eulav]) AT TIME ZONE ''UTC'' AT TIME ZONE ''Eastern Standard Time''), 23)
			ELSE [eulav]
		END AS [eulav]
	FROM (
		SELECT
			a.row_num
			,b.[key] AS [yek]
			,b.value AS [eulav]
		FROM (
			SELECT
				[value]
				,[key] AS row_num
			FROM
			OPENJSON('''+@json_body+''')
		) AS a
		CROSS APPLY OPENJSON([value], ''$'') AS b
	) AS x
) AS j
PIVOT
(
MAX(eulav) FOR [yek] IN ('
+ STUFF(REPLACE(@columns_pivot, ', p.[', ', ['), 1, 1, '')
+ ')
) AS p';



SELECT @matching_pk_ids_query = N'
SELECT @matching_pk_ids = COUNT(*) FROM (
	SELECT
		b.[key]
		,b.value
	FROM (
		SELECT
			value
			,[key] AS row_num
		FROM
		OPENJSON('''+@json_body+''')
	) AS a
	CROSS APPLY OPENJSON(value, ''$'') AS b
	WHERE b.[key] = ''pk_id''
) AS x
JOIN ['+@dest_table_name+'] AS y
ON x.value = y.pk_id
'


	
-- If transaction payload has a column with pk_id,
-- UPDATE
IF @columns_pivot LIKE '%pk_id%'
	BEGIN
	EXEC SP_EXECUTESQL @matching_pk_ids_query, N'@matching_pk_ids INT OUTPUT', @matching_pk_ids = @matching_pk_ids OUTPUT
	IF @matching_pk_ids = 0
		THROW 50002, 'You gone done it now A-A-RON.', 1;
	ELSE

		SELECT @sql_transact_query = 'UPDATE a
SET
'+@columns_for_update+'
FROM ['+@dest_table_name+'] AS a
JOIN (
'+@sql_data_query+'
) AS b
ON a.pk_id = b.pk_id;';

	END
	
-- INSERT
ELSE 
	BEGIN
	SELECT @sql_transact_query = 'INSERT INTO ['+@dest_table_name+']
'+@columns_for_insert +'
'+@sql_data_query+';'
END

--PRINT @sql_transact_query;
SELECT @output_query = @sql_transact_query;
IF @execute = 1
	--BEGIN
	EXEC SP_EXECUTESQL @sql_transact_query;
END

GO


