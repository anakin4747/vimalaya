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
                ['himalaya envelope list --mailbox Inbox --json --page-size 100'] = 'tests/envelopes.json',
                ['himalaya message read --mailbox Inbox 1'] = 'tests/message.txt',
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

    it("does not call nvim_buf_is_valid in a fast event context", function()
        -- Prevent E5560: nvim_buf_is_valid must not be called in a fast event context.
        local schedule = vim.schedule
        local is_valid = vim.api.nvim_buf_is_valid
        local scheduled = false
        local accessed_in_callback = false

        vim.schedule = function(callback)
            schedule(function()
                scheduled = true
                callback()
                scheduled = false
            end)
        end
        vim.api.nvim_buf_is_valid = function(bufnr)
            accessed_in_callback = accessed_in_callback or not scheduled
            return is_valid(bufnr)
        end
        vim.system = function(_, _, callback)
            callback({
                code = 0,
                stdout = table.concat(vim.fn.readfile('tests/mailboxes.json'), '\n'),
                stderr = '',
            })
        end

        vim.cmd('Mail')
        assert.is_true(vim.wait(1000, function()
            return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == 'Inbox'
        end))
        vim.schedule = schedule
        vim.api.nvim_buf_is_valid = is_valid

        assert.is_false(accessed_in_callback)
    end)

    it("creates a new buffer", function()
        local count = #vim.api.nvim_list_bufs()
        vim.cmd('Mail')
        assert.equal(count + 1, #vim.api.nvim_list_bufs())
    end)

    it("names the main menu buffer", function()
        vim.cmd('Mail')

        assert.is_true(vim.startswith(
            vim.api.nvim_buf_get_name(0),
            vim.fn.fnamemodify(vim.fn.tempname(), ':h') .. '/'
        ))
    end)

    it("makes the main menu buffer readonly", function()
        vim.cmd('Mail')

        assert.is_true(vim.bo.readonly)
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

    local function open_inbox_mailbox()
        vim.cmd('Mail')
        assert.is_true(vim.wait(1000, function()
            return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == 'Inbox'
        end))
        local main_menu = vim.api.nvim_get_current_buf()

        vim.api.nvim_feedkeys(vim.keycode('<CR>'), 'x', false)
        return main_menu
    end

    it("opens a mailbox buffer", function()
        local main_menu = open_inbox_mailbox()

        assert.is_true(vim.wait(1000, function()
            return vim.api.nvim_get_current_buf() ~= main_menu
        end))
    end)

    it("names mailbox buffers", function()
        open_inbox_mailbox()

        assert.is_true(vim.startswith(
            vim.api.nvim_buf_get_name(0),
            vim.fn.fnamemodify(vim.fn.tempname(), ':h') .. '/'
        ))
        assert.is_true(vim.endswith(vim.api.nvim_buf_get_name(0), ' vimalaya Inbox mailbox'))
    end)

    it("makes mailbox buffers readonly", function()
        open_inbox_mailbox()

        assert.is_true(vim.bo.readonly)
    end)

    it("lists envelopes in mailbox buffers", function()
        open_inbox_mailbox()

        assert.is_true(vim.wait(1000, function()
            return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == '2026-01-01T00:00:00Z First example message'
        end))
        assert.same({
            '2026-01-01T00:00:00Z First example message',
            '2026-01-02T00:00:00Z Second example message',
            '2026-01-03T00:00:00Z Third example message',
        }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
    end)

    it("opens a message buffer from an envelope", function()
        open_inbox_mailbox()
        assert.is_true(vim.wait(1000, function()
            return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == '2026-01-01T00:00:00Z First example message'
        end))
        local mailbox = vim.api.nvim_get_current_buf()

        vim.api.nvim_feedkeys(vim.keycode('<CR>'), 'x', false)

        assert.is_true(vim.wait(1000, function()
            return vim.api.nvim_get_current_buf() ~= mailbox
        end))
        assert.is_true(vim.wait(1000, function()
            return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == 'From: Example Sender <sender@example.test>'
        end))
        assert.same(vim.fn.readfile('tests/message.txt'), vim.api.nvim_buf_get_lines(0, 0, -1, false))
    end)

    it("backs message buffers with temporary files", function()
        open_inbox_mailbox()
        assert.is_true(vim.wait(1000, function()
            return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == '2026-01-01T00:00:00Z First example message'
        end))

        vim.api.nvim_feedkeys(vim.keycode('<CR>'), 'x', false)
        assert.is_true(vim.wait(1000, function()
            return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == 'From: Example Sender <sender@example.test>'
        end))

        vim.cmd('write')
        assert.equal(1, vim.fn.filereadable(vim.api.nvim_buf_get_name(0)))
    end)

    it("names email buffers after their subject", function()
        open_inbox_mailbox()
        assert.is_true(vim.wait(1000, function()
            return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == '2026-01-01T00:00:00Z First example message'
        end))

        vim.api.nvim_feedkeys(vim.keycode('<CR>'), 'x', false)

        assert.is_true(vim.wait(1000, function()
            return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == 'From: Example Sender <sender@example.test>'
        end))
        assert.is_true(vim.endswith(vim.api.nvim_buf_get_name(0), ' vimalaya First example message'))
    end)

    it("makes email buffers writable", function()
        open_inbox_mailbox()
        assert.is_true(vim.wait(1000, function()
            return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == '2026-01-01T00:00:00Z First example message'
        end))

        vim.api.nvim_feedkeys(vim.keycode('<CR>'), 'x', false)
        assert.is_true(vim.wait(1000, function()
            return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == 'From: Example Sender <sender@example.test>'
        end))

        assert.is_false(vim.bo.readonly)
    end)

    it("restores an email after deleting its buffer", function()
        open_inbox_mailbox()
        assert.is_true(vim.wait(1000, function()
            return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == '2026-01-01T00:00:00Z First example message'
        end))
        local mailbox = vim.api.nvim_get_current_buf()

        vim.api.nvim_feedkeys(vim.keycode('<CR>'), 'x', false)
        assert.is_true(vim.wait(1000, function()
            return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == 'From: Example Sender <sender@example.test>'
        end))
        vim.api.nvim_buf_set_lines(0, 0, 1, false, { 'Modified message' })
        vim.api.nvim_buf_delete(0, { force = true })
        vim.api.nvim_set_current_buf(mailbox)

        vim.api.nvim_feedkeys(vim.keycode('<CR>'), 'x', false)
        assert.is_true(vim.wait(1000, function()
            return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == 'From: Example Sender <sender@example.test>'
        end))
        assert.same(vim.fn.readfile('tests/message.txt'), vim.api.nvim_buf_get_lines(0, 0, -1, false))
    end)

    it("reuses an open email buffer", function()
        open_inbox_mailbox()
        assert.is_true(vim.wait(1000, function()
            return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == '2026-01-01T00:00:00Z First example message'
        end))
        local mailbox = vim.api.nvim_get_current_buf()

        vim.api.nvim_feedkeys(vim.keycode('<CR>'), 'x', false)
        assert.is_true(vim.wait(1000, function()
            return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == 'From: Example Sender <sender@example.test>'
        end))
        local expected = vim.api.nvim_get_current_buf()
        vim.api.nvim_set_current_buf(mailbox)

        vim.api.nvim_feedkeys(vim.keycode('<CR>'), 'x', false)

        assert.equal(expected, vim.api.nvim_get_current_buf())
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

    it("close closes all vimalaya buffers", function()
        local unrelated = vim.api.nvim_create_buf(true, false)
        local main_menu = open_inbox_mailbox()
        assert.is_true(vim.wait(1000, function()
            return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == '2026-01-01T00:00:00Z First example message'
        end))
        local mailbox = vim.api.nvim_get_current_buf()
        vim.api.nvim_feedkeys(vim.keycode('<CR>'), 'x', false)
        assert.is_true(vim.wait(1000, function()
            return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == 'From: Example Sender <sender@example.test>'
        end))
        local message = vim.api.nvim_get_current_buf()

        vim.cmd('Mail close')

        assert.is_false(vim.api.nvim_buf_is_valid(main_menu))
        assert.is_false(vim.api.nvim_buf_is_valid(mailbox))
        assert.is_false(vim.api.nvim_buf_is_valid(message))
        assert.is_true(vim.api.nvim_buf_is_valid(unrelated))
    end)
end)
