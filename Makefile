# make install            install for every supported terminal on this machine
# make install rex        install for only these: herdr, herdr-tui, rex, ghostty
# make uninstall
# make test

TERMINALS := $(filter herdr herdr-tui rex ghostty,$(MAKECMDGOALS))

.PHONY: install uninstall test herdr herdr-tui rex ghostty

install:
	./install.sh $(TERMINALS)

uninstall:
	./install.sh --uninstall

test:
	bash tests/run.sh

# Terminal names are arguments to install, not targets of their own.
herdr herdr-tui rex ghostty:
	@:
