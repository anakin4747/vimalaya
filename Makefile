
.PHONY: make
make:
	@./scripts/cqfd exec make test

.PHONY: test
test:
	@nvim \
		--headless \
		--noplugin \
		-u tests/test_init.lua \
		-c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/test_init.lua' }" \
		| grep -v '/tmp/nvim' \
		| grep -v 'Message successfully sent'
	@cog check
