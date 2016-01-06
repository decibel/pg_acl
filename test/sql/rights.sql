\set ECHO none

\i test/pgxntool/setup.sql

-- TODO: remove
SET search_path=public,tap;


SELECT plan(7);

-- NOTE: the compat.sql test verifies that we've got the full set of rights
-- Sanity-check with grant version
SELECT is(
  length(_aclitems_all_rights_w_grant())
  , length(_aclitems_all_rights_no_grant()) * 2
  , '_aclitems_all_rights_w_grant is 2x longer than without.'
);
SELECT is(
  _aclitems_all_rights_no_grant()
  , _aclitems_all_rights_no_grant()
  , '_aclitems_all_rights_w_grant with *s removed matches without grants'
);

SELECT is(
  _all__acl_right()
  , _all__acl_right_no_grant()::acl_right[] || _all__acl_right_only_grant()
  , 'Verify all values are in _all__acl_right()'
);


-- Function output
SELECT is(
  rights_to_enum_no_grant(_aclitems_all_rights_no_grant())
  , _all__acl_right_no_grant()
  , 'rights_to_enum_no_grant() output correct'
);
-- ASSUMPTION: rights_to_enum_no_grant() internally calls rights_to_enum(...,true)
SELECT is(
  rights_to_enum(_aclitems_all_rights_w_grant())
  , _all__acl_right_only_grant()
  , 'rights_to_enum() output correct'
);

-- Function return types should be different
SELECT function_returns(
  'rights_to_enum_no_grant'::name
  , '{text}'::text[]
  , 'acl_right_no_grant[]'
);
SELECT function_returns(
  'rights_to_enum_no_grant'::name
  , '{text}'::text[]
  , 'acl_right_no_grant[]'
);

SELECT * FROM finish();

\echo # TRANSACTION INTENTIONALLY LEFT OPEN!

-- vi: expandtab sw=2 ts=2
