CREATE OR REPLACE FUNCTION _aclitems_all_rights_no_grant(
) RETURNS text LANGUAGE sql IMMUTABLE AS $body$
SELECT 'arwdDxtXUCTc'::text;
$body$;
CREATE OR REPLACE FUNCTION _aclitems_all_rights_w_grant(
) RETURNS text LANGUAGE sql IMMUTABLE AS $body$
SELECT array_to_string(
    regexp_split_to_array( _aclitems_all_rights_no_grant(), '' )
    , '*'
  ) || '*'
$body$;

@generated@
CREATE OR REPLACE FUNCTION _enum_from_array(
  enum_name text
  , enum_values text[]
  , comment text DEFAULT NULL
) RETURNS void LANGUAGE plpgsql AS $_enum_from_array$
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
      'COMMENT ON TYPE %I IS %L'
      , enum_name
      , comment
    );
    RAISE DEBUG 'sql = %', sql;
    EXECUTE sql;
  END IF;

  /*
   * Create functions that return all the enum values.
   */
  array_function_name = '_all__' || enum_name;
  sql := format(
$format$CREATE OR REPLACE FUNCTION %1$I(
) RETURNS %2$I[] LANGUAGE sql IMMUTABLE AS $body$
SELECT enum_range(NULL::%2$I)
$body$;
COMMENT ON FUNCTION %1$I() IS %L;
$format$
    , array_function_name
    , enum_name
    , 'Returns all values of enum ' || enum_name || '.'
  );
  RAISE DEBUG 'sql = %', sql;
  EXECUTE sql;

  sql := format(
$format$CREATE OR REPLACE FUNCTION %1$I(
) RETURNS SETOF %2$I LANGUAGE sql IMMUTABLE AS $body$
SELECT * FROM unnest(%3$I())
$body$;

@generated@

COMMENT ON FUNCTION %1$I() IS %4$L;
$format$
    , array_function_name || '_srf'
    , enum_name
    , array_function_name
    , 'Returns all values of enum ' || enum_name || '.'
  );
  RAISE DEBUG 'sql = %', sql;
  EXECUTE sql;

END
$_enum_from_array$;
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

@generated@

-- Create ENUM that includes WITH GRANT
SELECT _enum_from_array(
  'acl_right'
  , array(
      SELECT r FROM (
        SELECT r::text, ordinality FROM _all__acl_right_no_grant_srf() WITH ORDINALITY r
        UNION ALL
        SELECT r || ' WITH GRANT OPTION', ordinality FROM _all__acl_right_no_grant_srf() WITH ORDINALITY r
      ) a
      ORDER BY ordinality, r
    )
  , $$Rights that an ACL item can have.$$
);

-- Only GRANT version of rights
CREATE FUNCTION _all__acl_right_only_grant_srf(
) RETURNS SETOF acl_right LANGUAGE sql IMMUTABLE AS $body$
SELECT * FROM _all__acl_right_srf() r WHERE r::text LIKE '% WITH GRANT OPTION'
$body$;
CREATE FUNCTION _all__acl_right_only_grant(
) RETURNS acl_right[] LANGUAGE sql IMMUTABLE AS $body$
SELECT array( SELECT * FROM _all__acl_right_only_grant_srf() )
$body$;

@generated@

CREATE CAST (acl_right AS acl_right_no_grant) WITH INOUT;
CREATE CAST (acl_right_no_grant AS acl_right) WITH INOUT;

CREATE OR REPLACE FUNCTION _rights_to_enum(
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

@generated@

COMMENT ON FUNCTION _rights_to_enum(
  input text
  , no_grant boolean
) IS $$Parse the rights portion of an aclitem. If no_grant is true then grant options will be ignored.$$;

CREATE OR REPLACE FUNCTION _rights_to_enum_no_grant(
  input text
) RETURNS acl_right_no_grant[] LANGUAGE sql IMMUTABLE AS $body$
SELECT _rights_to_enum(input, true)::acl_right_no_grant[]
$body$;


CREATE TYPE acl AS (
  grantee "regrole"
  , rights acl_right[]
  , grantor "regrole"
);

@generated@

CREATE OR REPLACE FUNCTION acl(
  input aclitem
) RETURNS acl LANGUAGE plpgsql
STABLE -- regrole is only stable
AS $body$
DECLARE
  c_equal CONSTANT text[] := string_to_array( input::text, '=' );
  c_slash CONSTANT text[] := string_to_array( c_equal[2], '/' );

  o acl;
BEGIN
  IF array_length(c_equal, 1) > 2 THEN
    RAISE 'parsing roles that contain equals ("=") is not supported'
    USING
      hint='If you need support for this please open an issue at https://github.com/decibel/pg_acl/issues!'
    ;
  END IF;
  IF array_length(c_slash, 1) > 2 THEN
    RAISE 'parsing roles that contain slash ("/") is not supported'
    USING
      hint='If you need support for this please open an issue at https://github.com/decibel/pg_acl/issues!'
    ;
  END IF;

  o.grantee = nullif(c_equal[1], '');
  o.grantor = nullif(c_slash[2], '');
  o.rights = _rights_to_enum(c_slash[1]);
  RETURN o;
END
$body$;
CREATE OR REPLACE FUNCTION acl(
  input aclitem[]
) RETURNS acl[] LANGUAGE sql STABLE AS $body$
SELECT array(
  SELECT acl(u) FROM unnest(input) u
)
$body$;

@generated@

/* TODO
#define ACL_ALL_RIGHTS_COLUMN		(ACL_INSERT|ACL_SELECT|ACL_UPDATE|ACL_REFERENCES)
#define ACL_ALL_RIGHTS_RELATION		(ACL_INSERT|ACL_SELECT|ACL_UPDATE|ACL_DELETE|ACL_TRUNCATE|ACL_REFERENCES|ACL_TRIGGER)
#define ACL_ALL_RIGHTS_SEQUENCE		(ACL_USAGE|ACL_SELECT|ACL_UPDATE)
#define ACL_ALL_RIGHTS_DATABASE		(ACL_CREATE|ACL_CREATE_TEMP|ACL_CONNECT)
#define ACL_ALL_RIGHTS_FDW			(ACL_USAGE)
#define ACL_ALL_RIGHTS_FOREIGN_SERVER (ACL_USAGE)
#define ACL_ALL_RIGHTS_FUNCTION		(ACL_EXECUTE)
#define ACL_ALL_RIGHTS_LANGUAGE		(ACL_USAGE)
#define ACL_ALL_RIGHTS_LARGEOBJECT	(ACL_SELECT|ACL_UPDATE)
#define ACL_ALL_RIGHTS_NAMESPACE	(ACL_USAGE|ACL_CREATE)
#define ACL_ALL_RIGHTS_TABLESPACE	(ACL_CREATE)
#define ACL_ALL_RIGHTS_TYPE			(ACL_USAGE)
*/

-- vi: expandtab ts=2 sw=2
