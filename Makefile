
.PHONY: make
make:
	./scripts/cqfd init
	./scripts/cqfd exec make test

.PHONY: test
test:
	cog check
	@nvim \
		--headless \
		--noplugin \
		-u tests/test_init.lua \
		-c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/test_init.lua' }" | grep -v '/tmp/nvim'
