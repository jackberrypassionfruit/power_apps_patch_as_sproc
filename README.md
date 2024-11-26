# Power Apps Patch() as Stored Procedure

An (almost) drop-in replacement for the Power Apps Patch() function in the form of a SQL Stored Procedure

## Root Problem

What's wrong with the Patch() function?

2 Things:
1. Dropped Transactions
    - I may just be crazy, but after working with Power Apps for a few years I have noticed instances where sequential Patch() statements in one button click don't seem to succeed.
    - Before you ask, yes, I have tried Concurrent().
    - I have sometimes mitigated it by turning multiple Patch() statements into one, if they were to the same data source. But that is usually not an option.
    - Offloading the opaque Patch() -> SQL Server connector in favor of this custom SQL Stored Procedure has not yielded any "dropped transactions" for me.
2. SQL Transaction Rollback
    - Another gripe I have with Patch() is that, when you execute multiple of them in one action, they have no knowledge of each others' results.
    - This means that if you click a button with 5 Patch statements, and 3 are successful but the 4th one fails, now you have 3 tables with wonky data you need to clean up.
    - Concurrent does not address this problem. It only allows parallel execution, but otherwise the executions still don't know about each other.
    - Once again, this custom Stored Procedure leverages SQL's nifty ability to rollback transactions if any part of it has failed
    - See this article learn more about SQL Server's transaction rollback functionality:
    - [SET XACT_ABORT (Transact-SQL)](https://learn.microsoft.com/en-us/sql/t-sql/statements/set-xact-abort-transact-sql?view=sql-server-ver16)
    - One Caveat to note while debugging: 
        - This is the default behavior in a SQL trigger, like a Stored Procedure.
        - It is NOT default behaviour in a T-SQL statement, like when debugging

## Pros / Cons Analysis
- As you've seen, there are some benefits to avoiding the built-in Patch() function
- However, there are also drawbacks:
    1. No table schema validation
        - Part of Patch()'s functionality is that it knows the base SQL table's schema, and thus can throw errors when it knows that the payload sent with Patch() would not be successful
        - Since the table schema is not known to the Stored Procedure until *runtime*, there is no indication ahead of time that the transaction will fail
            - (However, if your error checker also lags and needs to be reset by deleting re-creating all patch statements before it works again, you might view this as a plus)
    2. The inputs to the Stored Procedure are more complicated than for Patch()
        - Patch() can accept the native Power Fx object of *Collection*, and batch its payload into columns and rows accordingly
        - Stored Procedures only accept *Strings* (as far as I know), which means that the collection has to be converted to a string of JSON to be used in the Stored Procedure
        - *See API notes in the next section*

## How to Use in Power Apps - INSERT
- As expected, the API for using this stored procedures is different from that of the Patch() function:

    - In Power Apps Patch():
        - [Patch Function](https://learn.microsoft.com/en-us/power-platform/power-fx/reference/function-patch)
        - Syntax: 
        ```
        Concurrent(
            Patch( 'Table1', [ data1-as-collection ] ),
            Patch( 'Table2', [ data2-as-collection ] )
        )
        ```
        - ex. 
        ```
        Concurrent(
            Patch( 
                'Customers', 
                { 
                    name: "Leroy Jenksins",
                    occupations: "Raider"
                }
            ),
            Patch( 
                'Sellers', 
                { 
                    name: "Potion Seller",
                    occupations: "Sells Potions"
                }
            )
        )
        ```
    - In Stored Procedure Patch():
        - Syntax:
        ```
        DB.SP.Patch_Concurrent({
            dest_tables_names: 
                "pipe-separated table names",
            json_bodies:
                "pipe-separated data as JSON"
        })
        ```
        - ex.
        ```
        ClearCollect(
            data_customer,
            { 
                name: "Leroy Jenksins",
                occupations: "Raider"
            }
        );
        ClearCollect(
            data_seller,
            { 
                name: "Potion Seller",
                occupations: "Sells Potions"
            }
        );

        UpdateContext({
            dest_table_list: [ "Customers",     "Sellers"   ],
            json_body_list:  [ data_customer,   data_seller ]
        });
        
        UpdateContext({
            dest_table_json: Concat(dest_table_list, Value, "|"),
            json_body_json:  Concat(json_body_list, JSON(Value, JSONFormat.IndentFour), "|")
        });

        DB.SP.Patch_Concurrent({
            dest_tables_names:  dest_table_json,
            json_bodies:        json_body_json
        })
        ```
    - There is a bit more work to package the data in a format the Stored Procedure can parse.
    - FUTURE IMROVEMENT: If you want contribute, improving the API here would be a great place to start.

## How to Use in Power Apps - UPDATE
- The Stored Procedure can also be used to UPDATE tables in SQL Server as well!
- Just like Patch(), this is done by passing JSON where one of the column is the primary key of the table
- However, because my team only ever uses "pk_id" as the primary key of the table, I have hardcoded that as the value to indicate that the desired functionality is UDPATE
- FUTURE IMPROVEMENT: This can be generalized by allow another argument to be passed: 
    - The primary key of the table to update on

## Installing the Stored Procedures
- In SQL Server
    - [SP_Transact_Patch] can be CREATEd to execute SQL queries as a standalone SProc
    - [SP_Transact_Patch_Concurrent] relies on the former being CREATEd, since it helps build the concurrent transaction from each query
- In Power Apps
    - By default, when you import your Stored Procedure it will have the name of your database
    - You can rename that to something shorter and easier to type, and user like the above syntax