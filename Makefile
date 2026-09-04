# Forward all make targets to sim/Makefile
.PHONY: all compile compile-all sim run test test-all wave smoke clean help

all compile compile-all sim run test test-all wave smoke clean help:
	$(MAKE) -C sim $@

# Catch-all fallback to forward any custom target
%:
	@$(MAKE) -C sim $@
