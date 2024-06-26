--
-- json debugging
--

CREATE OR REPLACE FUNCTION read_json_file()
RETURNS text
AS $$
DECLARE
    file_path text;
    system_id text;
    pg_version text;
    file_content text;
BEGIN
    SELECT latest_output_filename INTO file_path FROM percona_pg_telemetry_status();
    SELECT system_identifier::TEXT INTO system_id FROM pg_control_system();
    SELECT version() INTO pg_version;

    file_content := pg_read_file(file_path);

    RETURN file_content;
END;
$$ LANGUAGE plpgsql;

-- Let's sleep for a few seconds to ensure that leader has
-- generated the json file.
SELECT pg_sleep(3);

CREATE EXTENSION percona_pg_telemetry;

SELECT  'matches' AS db_instance_id
FROM    pg_control_system()
WHERE   '"' || system_identifier || '"' = (SELECT CAST(read_json_file()::JSON->'db_instance_id' AS VARCHAR));

SELECT  'matches' AS pillar_version
WHERE   '"' || current_setting('server_version') || '"' = (SELECT CAST(read_json_file()::JSON->'pillar_version' AS VARCHAR));

SELECT  'matches' AS settings
FROM    pg_settings
WHERE   name NOT LIKE 'plpgsql.%' AND vartype != 'string'
HAVING  COUNT(*) = (SELECT json_array_length(read_json_file()::JSON->'settings'));

SELECT  'matches' AS databases_count
FROM    pg_database
WHERE   datallowconn = true
HAVING  COUNT(*) = (
                    SELECT CAST(
                                    REPLACE(
                                                CAST(read_json_file()::JSON->'databases_count' AS VARCHAR)
                                                , '"', ''
                                            )
                                    AS INTEGER
                                )
                            + CAST(NOT EXISTS (SELECT * FROM pg_settings where name = 'percona_pg_telemetry.path') AS INTEGER)
                );
-- Databases count will fail if you have any preexisting databases other than the standard template1 and postgres

SELECT  'matches' AS databases_count_calc
FROM    pg_database
WHERE   datallowconn = true
HAVING  COUNT(*) = (
                    SELECT  json_array_length(read_json_file()::JSON->'databases')
                            + CAST(NOT EXISTS (SELECT * FROM pg_settings where name = 'percona_pg_telemetry.path') AS INTEGER)
                );
-- Databases count will fail if you have any preexisting databases other than the standard template1 and postgres

DROP EXTENSION percona_pg_telemetry;
DROP FUNCTION read_json_file;
