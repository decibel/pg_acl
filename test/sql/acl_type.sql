\set ECHO none

/*
 * Note! This file must be named acl_type so that it's not the same as the top-level sql/acl.sql!
 *
 * http://www.postgresql.org/message-id/56899F36.9000607@BlueTreble.com
 */

\set test_role "acl test role: really bad role that contains "" and spaces"

-- Do this before we're in the transaction to clean up anything we accidentally committed
SET client_min_messages = WARNING;
DROP ROLE IF EXISTS :test_role;

\i test/pgxntool/setup.sql

-- TODO: remove
SET search_path=public,tap;

-- NOTE: the compat.sql test verifies that we've got the full set of rights


SELECT plan(6);
SAVEPOINT start;

SELECT is(
  acl( ('=' || _aclitems_all_rights_no_grant() || '/' || current_user)::aclitem )
  , ( NULL, _all__acl_right_no_grant(), current_user )::acl
  , 'acl() with all no grant rights'
);
SELECT is(
  acl( ('=' || _aclitems_all_rights_w_grant() || '/' || current_user)::aclitem )
  , ( NULL, _all__acl_right_only_grant(), current_user )::acl
  , 'acl() with all grant rights'
);

CREATE ROLE :test_role;
SAVEPOINT test_role;
SELECT lives_ok(
  format( $$SELECT (%L || '=adrw/%s')::aclitem$$, :'test_role', current_user )
  , 'Simple cast of test role to aclitem'
);
SELECT lives_ok(
  format( $$SELECT ('=adrw/' || %L)::aclitem$$, :'test_role' )
  , 'Simple cast of test role to aclitem as grantor'
);

SELECT is(
  acl( ('=a/' || :'test_role' )::aclitem )
  , ( NULL, '{INSERT}', :'test_role' )::acl
  , 'acl() with test role'
);
SELECT is(
  acl( (:'test_role' || '=a/' || current_user )::aclitem )
  , ( :'test_role', '{INSERT}', current_user )::acl
  , 'acl() with test role grantor'
);

SELECT * FROM finish();

\echo # TRANSACTION INTENTIONALLY LEFT OPEN!

-- vi: expandtab sw=2 ts=2
