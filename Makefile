SOURCES := $(wildcard tests/*/*.d)

%.result: % %.ast Makefile
	@rdmd astdump $< > $<.tmp
	@git diff --no-index $<.tmp $<.ast && echo -ne "\x1b[32;01mOK" || echo -ne "\x1b[31;01mFAIL"
	@echo -e "\x1b[0m $<"
	@rm -Rf $<.tmp

tests: $(SOURCES:=.result)
