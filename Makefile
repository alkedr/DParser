SOURCES = $(sort $(wildcard tests/*/*.d))

.PHONY: tests/generated

tests: tests.d Makefile
	@rdmd -debug $<

%.result: % %.ast Makefile
	@rdmd astdump $< > $<.tmp
	@cmp -s $<.tmp $<.ast && echo -e "\x1b[32;01mOK\x1b[0m $<" || echo -e "\n\x1b[31;01mFAIL\x1b[0m $<"
	@git diff --no-index --color $<.tmp $<.ast | tail -n +6
	@cmp -s $<.tmp $<.ast || echo
	@rm -Rf $<.tmp

old-tests: $(SOURCES:=.result)
