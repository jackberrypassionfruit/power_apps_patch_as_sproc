SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE PROCEDURE [dbo].[SP_Transact_Patch_Concurrent] 
	@json_bodies nvarchar(MAX),
    @dest_table_names nvarchar(2000),
	@query_to_execute NVARCHAR(MAX) OUTPUT
AS

DECLARE @table_name		NVARCHAR(1000);
DECLARE @json_body		NVARCHAR(MAX);
DECLARE @output_query	NVARCHAR(MAX);

SET @query_to_execute = N'';

-- JOIN the tables and the JSON rows, so the cursor can execute on them in pairs
DECLARE Row_Cursor CURSOR FOR

SELECT
	a.json_body
	,b.table_name
FROM 
( 
	SELECT 
		Value AS json_body 
		,ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS row_num
	FROM STRING_SPLIT(@json_bodies, '|')	
) AS  a
JOIN
( 
	SELECT 
		Value AS table_name 
		,ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS row_num
	FROM STRING_SPLIT(@dest_table_names, '|') 
) AS  b
ON a.row_num = b.row_num

	
OPEN Row_Cursor;
	
-- Perform the first fetch and store the values in variables.  
FETCH NEXT FROM Row_Cursor
INTO @json_body, @table_name;

	
-- Check @@FETCH_STATUS to see if there are any more rows to fetch.  
WHILE @@FETCH_STATUS = 0  
BEGIN  

-- Strangely, SQL variable assignments coming from Stored Proc outcomes assign to the right, unlike other languages
EXEC [dbo].[SP_Transact_Patch] @json_body, @table_name, 0, @output_query = @output_query OUTPUT
-- Add each query to the concurrent query
SET @query_to_execute += @output_query


FETCH NEXT FROM Row_Cursor
INTO @json_body, @table_name;
	
	
END

CLOSE Row_Cursor;
DEALLOCATE Row_Cursor;


--PRINT @query_to_execute;
EXEC sp_executesql @query_to_execute;

GO


