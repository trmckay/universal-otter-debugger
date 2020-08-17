NAME = otter-debugger
VERSION = v1.4
BUILD = $(NAME)-$(VERSION)
SHELL:=/bin/bash

module:
	@echo "Condensing SystemVerilog modules into one file..."
	echo "" > otter_debugger_$(VERSION).sv
	cat otter-adapter/db_adapter.sv >> otter_debugger_$(VERSION).sv
	for file in uart-db/module/design/*.sv; do (echo -e "\n" >> otter_debugger_$(VERSION).sv; cat $$file >> otter_debugger_$(VERSION).sv) done

release:
	@echo "Building documentation..."
	(cd doc; make)
	@echo "Building client..."
	(cd uart-db/client; make)
	@echo "Creating build directories..."
	mkdir -p $(BUILD)
	mkdir -p $(BUILD)/client
	mkdir -p $(BUILD)/module
	mkdir -p $(BUILD)/doc
	@echo "Saving documentation..."
	cp README.md $(BUILD)/doc
	cp doc/pdf/* $(BUILD)/doc
	@echo "Saving client binary and source..."
	cp -r uart-db/client/src $(BUILD)/client
	cp -r uart-db/client/build/* $(BUILD)/client
	@echo "Condensing SystemVerilog modules into one file..."
	echo "" > $(BUILD)/module/otter_debugger_$(VERSION).sv
	cat otter-adapter/db_adapter.sv >> $(BUILD)/module/otter_debugger_$(VERSION).sv
	for file in uart-db/module/design/*.sv; do (echo -e "\n" >> $(BUILD)/module/otter_debugger_$(VERSION).sv; cat $$file >> $(BUILD)/module/otter_debugger_$(VERSION).sv) done
	tar czf $(NAME)-$(VERSION).tar.gz $(BUILD)/*
	rm -r $(BUILD)

clean:
	(cd uart-db/client; make clean)
	(cd doc; make remove)
	rm -f $(NAME)-$(VERSION).tar.gz
