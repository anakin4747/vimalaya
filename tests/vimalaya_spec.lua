local busted = require("plenary.busted")
local describe = busted.describe
local it = busted.it
local before_each = busted.before_each
local after_each = busted.after_each


describe(":Mail", function()
    local system

    before_each(function()
        system = vim.system
        vim.system = function(command, _, callback)
            local fixtures = {
                ['himalaya mailbox list --json'] = 'tests/mailboxes.json',
            }
            local fixture = fixtures[table.concat(command, ' ')]
            assert.is_not_nil(fixture, 'unexpected command: ' .. table.concat(command, ' '))

            vim.schedule(function()
                callback({
                    code = 0,
                    stdout = table.concat(vim.fn.readfile(fixture), '\n'),
                    stderr = '',
                })
            end)
        end

        -- delete all buffers
        for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
            vim.api.nvim_buf_delete(bufnr, { force = true })
        end
    end)

    after_each(function()
        vim.system = system
    end)

    it("does not error", function()
        assert.has_no.errors(function()
            vim.cmd('Mail')
        end)
    end)

    it("creates a new buffer", function()
        local count = #vim.api.nvim_list_bufs()
        vim.cmd('Mail')
        assert.equal(count + 1, #vim.api.nvim_list_bufs())
    end)

    it("names the main menu buffer", function()
        vim.cmd('Mail')

        assert.equal(vim.fn.getcwd() .. '/vimalaya main menu', vim.api.nvim_buf_get_name(0))
    end)

    it("lists mailboxes in the main menu", function()
        vim.cmd('Mail')

        assert.is_true(vim.wait(1000, function()
            return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == 'Inbox'
        end))
        assert.same({
            'Inbox',
            '[Gmail]/All Mail',
            '[Gmail]/Drafts',
            '[Gmail]/Important',
            '[Gmail]/Sent Mail',
            '[Gmail]/Spam',
            '[Gmail]/Starred',
            '[Gmail]/Trash',
        }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
    end)

    it("reuses a currently active buffer", function()
        vim.cmd('Mail')
        local expected = vim.api.nvim_buf_get_name(0)

        vim.cmd('Mail')
        local actual = vim.api.nvim_buf_get_name(0)

        assert.equal(expected, actual)
    end)

    it("reuses a currently hidden buffer", function()
        vim.cmd('Mail')
        local expected = vim.api.nvim_buf_get_name(0)

        vim.cmd('enew')
        vim.cmd('Mail')
        local actual = vim.api.nvim_buf_get_name(0)

        assert.equal(expected, actual)
    end)
end)
