NVIM_BIN ?= nvim
TESTS := \
	tests/config_registry_git.lua \
	tests/directory_browser.lua \
	tests/startup_worktree.lua \
	tests/native_interface.lua \
	tests/selector_adapters.lua \
	tests/workspace_buffer_isolation.lua \
	tests/workspace_layout_events.lua \
	tests/workspace_terminal.lua \
	tests/session_cold.lua \
	tests/branch_sessions.lua \
	tests/integration_adapters.lua \
	tests/super_tree_integration.lua

.PHONY: test syntax

test:
	@set -eu; for test in $(TESTS); do \
		echo "==> $$test"; \
		SUPER_PROJECT_TEST="$$test" $(NVIM_BIN) --headless -u tests/minimal_init.lua -c "lua dofile('tests/run.lua')"; \
	done

syntax:
	@$(NVIM_BIN) --headless -u NONE --cmd 'set runtimepath+=.' \
		-c "lua for _, pattern in ipairs({ 'lua/**/*.lua', 'plugin/**/*.lua', 'tests/**/*.lua' }) do for _, file in ipairs(vim.fn.glob(pattern, false, true)) do local chunk, err = loadfile(file); if not chunk then error(file .. ': ' .. err) end end end; print('Lua syntax OK')" \
		-c 'qa!'
