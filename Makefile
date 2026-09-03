# Forward all make targets to sim/Makefile
.PHONY: all compile sim run wave clean help

all compile sim run wave clean help:
	$(MAKE) -C sim $@
