# Copyright 2012-2019 Tail-f Systems AB
#
# See the file "LICENSE" for information on usage and redistribution
# of this file, and for a DISCLAIMER OF ALL WARRANTIES.

include ./include.mk

ifdef LUX_SELF_TEST
LUX_EXTRAS += test
endif

SUBDIRS = src $(C_SRC_TARGET) $(LUX_EXTRAS)
DIALYZER_PLT = .dialyzer_plt
DIALYZER_LOG = dialyzer.log

all debug install clean:
	@for d in $(SUBDIRS); do         \
	   if test ! -d $$d ; then        \
	       echo "=== Skipping subdir $$d" ; \
	   else                   \
	      (cd $$d && $(MAKE) $@) ; \
	   fi ;                        \
	done

xref:
	bin/lux --xref

dialyzer: $(DIALYZER_PLT)
	dialyzer --src src --src bin --plt $(DIALYZER_PLT) \
		 -Wunderspecs -Woverspecs \
		| tee $(DIALYZER_LOG)

$(DIALYZER_PLT):
	dialyzer --build_plt --output_plt $(DIALYZER_PLT) \
		--apps erts kernel stdlib runtime_tools xmerl inets

dialyzer_clean:
	rm -f $(DIALYZER_PLT) $(DIALYZER_LOG)

.PHONY: test
test:
	cd test && $(MAKE) all

test_clean:
	cd test && $(MAKE) clean

config_clean:
	$(MAKE) clean
	-rm -rf configure include.mk autom4te.cache config.status config.log *~
