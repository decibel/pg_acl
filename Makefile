include pgxntool/base.mk

# TODO: Remove once this is pulled into pgxntool
installcheck: pgtap

B = sql

LT95		 = $(call test, $(MAJORVER), -lt, 95)

$B:
	@mkdir -p $@

installcheck: $B/pg_acl.sql
EXTRA_CLEAN += $B/pg_acl.sql
$B/pg_acl.sql: sql/pg_acl.in.sql Makefile safesed
	(echo @generated@ && cat $< && echo @generated@) | sed -e 's#@generated@#-- GENERATED FILE! DO NOT EDIT! See $<#' > $@
ifeq ($(LT95),yes)
	./safesed $@ -e 's/"regrole"/name/g'
endif

