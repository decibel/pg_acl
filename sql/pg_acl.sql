CREATE TYPE acl_right_wo_grant AS ENUM(
    'INSERT'
    , 'SELECT'
    , 'UPDATE'
    , 'DELETE'
    , 'TRUNCATE'
    , 'REFERENCES'
    , 'TRIGGER'
    , 'EXECUTE'
    , 'USAGE'
    , 'CREATE'
    , 'TEMPORARY'
    , 'CONNECT'
);

CREATE OR REPLACE FUNCTION _aclitems_all_rights(
) RETURNS text LANGUAGE sql IMMUTABLE AS $body$
SELECT 'arwdDxtXUCTc'::text;
$body$;

CREATE OR REPLACE FUNCTION _all_rights_wo_grant(
) RETURNS acl_right_wo_grant[] LANGUAGE sql IMMUTABLE AS $body$
SELECT enum_range(NULL::acl_right_wo_grant)
$body$;
CREATE OR REPLACE FUNCTION _all_rights_wo_grant_srf(
) RETURNS SETOF acl_right_wo_grant LANGUAGE sql IMMUTABLE AS $body$
SELECT * FROM unnest(_all_rights_wo_grant())
$body$;

CREATE OR REPLACE FUNCTION _enum_from_array(
  enum_name text
  , enum_values text[]
) RETURNS void LANGUAGE plpgsql AS $body$
DECLARE
  c_quoted_values text[] := array(
    SELECT quote_literal(unnest) FROM unnest(enum_values)
  );
  sql text;
BEGIN
  sql := format(
    $fmt$CREATE TYPE %s AS ENUM ( %s )$fmt$
    , enum_name
    , array_to_string(c_quoted_values, ', ')
  );
  RAISE DEBUG 'sql = %', sql;
  EXECUTE sql;
END
$body$;

-- Create ENUM that includes WITH GRANT
SELECT _enum_from_array(
  'acl_right'
  , array(
      SELECT r::text FROM _all_rights_wo_grant_srf() r
      UNION ALL
      SELECT r || ' WITH GRANT' FROM _all_rights_wo_grant_srf() r
    )
);

CREATE OR REPLACE FUNCTION rights_to_enum(
  input text
) RETURNS acl_right[] LANGUAGE plpgsql IMMUTABLE AS $body$
DECLARE
  p int := 1;
  c "char";
  ar acl_right; -- NOTE: "right" is a reserved word
  out acl_right[];
BEGIN
  IF input IS NULL THEN
    RAISE 'acl rights may not be NULL' USING ERRCODE='syntax_error';
  ELSIF input = '' THEN
    RAISE 'no rights specified' USING ERRCODE='syntax_error';
  END IF;

  LOOP
    c := substr(input, p, 1);
    EXIT WHEN c='';
    
/*
 * Build with
SELECT format(
    '      WHEN %L THEN %L'
    , substr(_aclitems_all_rights(),ordinality::int,1)
    ,a
  )
  FROM _all_rights_wo_grant_srf() WITH ORDINALITY a;
  */
    ar := CASE c
       WHEN 'a' THEN 'INSERT'
       WHEN 'r' THEN 'SELECT'
       WHEN 'w' THEN 'UPDATE'
       WHEN 'd' THEN 'DELETE'
       WHEN 'D' THEN 'TRUNCATE'
       WHEN 'x' THEN 'REFERENCES'
       WHEN 't' THEN 'TRIGGER'
       WHEN 'X' THEN 'EXECUTE'
       WHEN 'U' THEN 'USAGE'
       WHEN 'C' THEN 'CREATE'
       WHEN 'T' THEN 'TEMPORARY'
       WHEN 'c' THEN 'CONNECT'
    END;

    IF ar IS NULL THEN
      RAISE 'invalid mode character: must be one of "%"'
        , _aclitems_all_rights()
        USING ERRCODE='invalid_text_representation'
      ;
    END IF;

    /*
     * Technically, the built-in parsing silently ignores a leading *. Since
     * you'll never get that output from aclitemout(), I choose to disallow it.
     */
    p = p+1;
    IF substr(input, p, 1) = '*' THEN
      p = p+1;
      ar := ar::text || ' WITH GRANT';
    END IF;

    out = out || ar;
  END LOOP;

  RETURN out;
END
$body$;

-- vi: expandtab ts=2 sw=2
