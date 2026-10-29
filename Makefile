# make install            install for every supported terminal on this machine
# make install rex        install for only these: rex, herdr, ghostty
# make uninstall
# make test

TERMINALS := $(filter rex herdr ghostty,$(MAKECMDGOALS))

.PHONY: install uninstall test rex herdr ghostty

install:
	./install.sh $(TERMINALS)

uninstall:
	./install.sh --uninstall

test:
	bash tests/run.sh

# Terminal names are arguments to install, not targets of their own.
rex herdr ghostty:
	@:
