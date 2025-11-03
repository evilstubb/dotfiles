all:
	install -d $(HOME)/.local/bin
	install -m 755 devbox.sh $(HOME)/.local/bin/devbox

.PHONY: all
