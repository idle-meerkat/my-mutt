## Process this file with automake to produce Makefile.in
include $(top_srcdir)/flymake.am

AUTOMAKE_OPTIONS = 1.6 foreign

if USE_GSS
GSSSOURCES = auth_gss.c
endif

if USE_SASL_CYRUS
AUTHENTICATORS = auth_sasl.c
else
if USE_SASL_GNU
AUTHENTICATORS = auth_sasl_gnu.c
else
AUTHENTICATORS = auth_anon.c auth_cram.c
endif
endif

EXTRA_DIST = README TODO auth_anon.c auth_cram.c auth_gss.c auth_oauth.c \
	auth_sasl.c auth_sasl_gnu.c

AM_CPPFLAGS = -I$(top_srcdir)

noinst_LIBRARIES = libimap.a
noinst_HEADERS = auth.h imap_private.h message.h

libimap_a_SOURCES = auth.c auth_login.c auth_oauth.c browse.c command.c \
        imap.c imap.h message.c utf7.c util.c $(AUTHENTICATORS) $(GSSSOURCES)
