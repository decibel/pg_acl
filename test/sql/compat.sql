\set ECHO none

\i test/pgxntool/setup.sql

-- TODO: remove
SET search_path=public,tap;

SELECT plan(1);

SELECT throws_like(
  $$SELECT '=abcdefghijklmnopqrstuvwxyz'::aclitem$$
  , format( '%% must be one of "%s"', _aclitems_all_rights_no_grant() )
  , 'Ensure _aclitems_all_rights() is correct.'
);

SELECT * FROM finish();

\echo TRANSACTION INTENTIONALLY LEFT OPEN!

-- vi: expandtab sw=2 ts=2
