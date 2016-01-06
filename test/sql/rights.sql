\set ECHO none

\i test/pgxntool/setup.sql

-- TODO: remove
SET search_path=public,tap;


SELECT plan( 5 + 2 + 2 + 2 );

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

SELECT bag_eq(
  $$SELECT * FROM _all__acl_right_srf()$$
  , $$SELECT r::acl_right FROM _all__acl_right_no_grant_srf() r UNION ALL SELECT * FROM _all__acl_right_only_grant_srf()$$
  , 'Verify all values are in _all__acl_right()'
);

SELECT results_eq(
  $$SELECT r FROM _all__acl_right_srf() WITH ORDINALITY r WHERE ordinality % 2 = 1$$
  , $$SELECT r::acl_right FROM _all__acl_right_no_grant_srf() r$$
  , 'Verify proper ordering of rights without grant'
);
SELECT results_eq(
  $$SELECT r FROM _all__acl_right_srf() WITH ORDINALITY r WHERE ordinality % 2 = 0$$
  , $$SELECT * FROM _all__acl_right_only_grant_srf()$$
  , 'Verify proper ordering of rights with grant'
);


-- Function output
SELECT is(
  _rights_to_enum_no_grant(_aclitems_all_rights_no_grant())
  , _all__acl_right_no_grant()
  , '_rights_to_enum_no_grant() output correct'
);
-- ASSUMPTION: _rights_to_enum_no_grant() internally calls _rights_to_enum(...,true)
SELECT is(
  _rights_to_enum(_aclitems_all_rights_w_grant())
  , _all__acl_right_only_grant()
  , '_rights_to_enum() output correct'
);

-- Function return types should be different
SELECT function_returns(
  '_rights_to_enum_no_grant'::name
  , '{text}'::text[]
  , 'acl_right_no_grant[]'
);
SELECT function_returns(
  '_rights_to_enum_no_grant'::name
  , '{text}'::text[]
  , 'acl_right_no_grant[]'
);


-- Casts exist
SELECT has_cast(
  'acl_right'
  , 'acl_right_no_grant'
);
SELECT has_cast(
  'acl_right_no_grant'
  , 'acl_right'
);

SELECT * FROM finish();

\echo # TRANSACTION INTENTIONALLY LEFT OPEN!

-- vi: expandtab sw=2 ts=2
