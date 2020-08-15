NAME = otter-debugger
VERSION = v1.3
BUILD = $(NAME)-$(VERSION)

release:
	(cd doc; make)
	(cd uart-db/client; make)
	mkdir -p $(BUILD)
	mkdir -p $(BUILD)/client
	mkdir -p $(BUILD)/module
	mkdir -p $(BUILD)/doc
	cp README.md $(BUILD)
	cp -r uart-db/client/src $(BUILD)/client
	cp -r uart-db/client/build/* $(BUILD)/client
	cp uart-db/module/design/* $(BUILD)/module
	cp otter-adapter/db_adapter.sv $(BUILD)/module
	tar czf $(NAME)-$(VERSION).tar.gz $(BUILD)/*
	rm -r $(BUILD)

clean:
	(cd uart-db/client; make clean)
	(cd doc; make remove)
	rm -f $(NAME)-$(VERSION).tar.gz
