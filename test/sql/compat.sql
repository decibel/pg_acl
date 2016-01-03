\set ECHO none

\i test/pgxntool/setup.sql

-- TODO: remove
SET search_path=public,tap;

SELECT plan(1);

SELECT throws_like(
  $$SELECT '=!@#$%^&&*()'::aclitem'$$
  , format( '% must be one of ""', _aclitems_all_rights() )
  , 'Ensure _aclitems_all_rights() is correct.'
);


\echo TRANSACTION INTENTIONALLY LEFT OPEN!

-- vi: expandtab sw=2 ts=2
