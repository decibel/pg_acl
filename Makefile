include pgxntool/base.mk

B = sql

LT95		 = $(call test, $(MAJORVER), -lt, 95)

$B:
	@mkdir -p $@

EXTRA_CLEAN += $B/pg_acl.sql
$B/pg_acl.sql: sql/pg_acl.in.sql Makefile
ifeq ($(LT95),yes)
	cat $< | sed -e 's/"regrole"/name/g' > $@
else
	cp $< $@
endif

