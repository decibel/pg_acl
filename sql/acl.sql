CREATE OR REPLACE FUNCTION _aclitems_all_rights_no_grant(
) RETURNS text LANGUAGE sql IMMUTABLE AS $body$
SELECT 'arwdDxtXUCTc'::text;
$body$;
CREATE OR REPLACE FUNCTION _aclitems_all_rights(
) RETURNS text LANGUAGE sql IMMUTABLE AS $body$
SELECT array_to_string(
    regexp_split_to_array( _aclitems_all_rights_no_grant(), '' )
    , '*'
  ) || '*'
$body$;

CREATE OR REPLACE FUNCTION _enum_from_array(
  enum_name text
  , enum_values text[]
  , comment text DEFAULT NULL
) RETURNS void LANGUAGE plpgsql AS $body$
DECLARE
  c_quoted_values text[] := array(
    SELECT quote_literal(unnest) FROM unnest(enum_values)
  );

  array_function_name text;
  sql text;
BEGIN
  sql := format(
    $fmt$CREATE TYPE %s AS ENUM ( %s )$fmt$
    , enum_name
    , array_to_string(c_quoted_values, ', ')
  );
  RAISE DEBUG 'sql = %', sql;
  EXECUTE sql;

  -- TODO: Get schema for newly created enum so stuff below won't poop
  IF comment IS NOT NULL THEN
    sql := format(
      'COMMENT ON ENUM %I IS %L'
      , enum_name
      , comment
    );
    RAISE DEBUG 'sql = %', sql;
    EXECUTE sql;
  END IF;

  /*
   * Create functions that return all the enum values.
   */
  array_function_name = '_all_' || enum_name;
  sql := format(
$format$CREATE OR REPLACE FUNCTION %I(
) RETURNS %I[] LANGUAGE sql IMMUTABLE AS $body$
SELECT enum_range(NULL::%1$I)
$body$;
COMMENT ON FUNCTION %I() IS %L;
$format$
    , array_function_name
    , enum_name
    , 'Returns all values of enum ' || enum_name || '.'
  );
  RAISE DEBUG 'sql = %', sql;
  EXECUTE sql;

  sql := format(
$format$CREATE OR REPLACE FUNCTION %I(
) RETURNS SETOF %I LANGUAGE sql IMMUTABLE AS $body$
SELECT * FROM unnest(%2I())
$body$;
COMMENT ON FUNCTION %I() IS %L;
$format$
    , array_function_name || '_srf'
    , enum_name
    , array_function_name
    , 'Returns all values of enum ' || enum_name || '.'
  );
  RAISE DEBUG 'sql = %', sql;
  EXECUTE sql;

END
$body$;
COMMENT ON FUNCTION _enum_from_array(text,text[],text) IS $$Utility function for creating an enum from an array of values.$$;

-- Create no-grant enum first
SELECT _enum_from_array(
  'acl_right_no_grant'
  , array[
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
    ]
  , $$Rights that an ACL item can have, excluding WITH GRANT OPTION.$$
);

-- Create ENUM that includes WITH GRANT
SELECT _enum_from_array(
  'acl_right'
  , array(
      SELECT r::text FROM _all_rights_no_grant_srf() r
      UNION ALL
      SELECT r || ' WITH GRANT OPTION' FROM _all_rights_no_grant_srf() r
    )
  , $$Rights that an ACL item can have.$$;
);

CREATE OR REPLACE FUNCTION rights_to_enum(
  input text
  , no_grant boolean DEFAULT false
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
  FROM _all_rights_no_grant_srf() WITH ORDINALITY a;
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
      RAISE 'invalid mode character "%": must be one of "%"'
        , c
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
      IF NOT no_grant THEN
        ar := ar::text || ' WITH GRANT OPTION';
      END IF;
    END IF;

    out = out || ar;
  END LOOP;

  RETURN out;
END
$body$;
COMMENT ON FUNCTION rights_to_enum(
  input text
  , no_grant boolean
) IS $$Parse the rights portion of an aclitem. If no_grant is true then grant options will be ignored.$$;

CREATE OR REPLACE FUNCTION rights_to_enum_no_grant(
  input text
) RETURNS acl_right_no_grant[] LANGUAGE sql IMMUTABLE AS $body$
SELECT rights_to_enum(input, true)
$body$;

-- vi: expandtab ts=2 sw=2