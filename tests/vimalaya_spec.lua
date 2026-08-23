local busted = require("plenary.busted")
local describe = busted.describe
local it = busted.it
local before_each = busted.before_each
local after_each = busted.after_each


describe(":Mail", function()
    local executable
    local notify
    local system

    before_each(function()
        executable = vim.fn.executable
        notify = vim.notify
        system = vim.system
        vim.system = function(command, _, callback)
            local fixtures = {
                ['himalaya mailbox list --json'] = 'tests/mailboxes.json',
                ['himalaya envelope list --mailbox Inbox --json --page-size 100'] = 'tests/envelopes.json',
                ['himalaya message read --mailbox Inbox 1'] = 'tests/message.txt',
            }
            local fixture = fixtures[table.concat(command, ' ')]
            if command[1] == 'himalaya' and command[2] == 'message' and command[3] == 'compose' then
                fixture = 'tests/send-suceeded.txt'
            end
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
        vim.fn.executable = executable
        vim.notify = notify
        vim.system = system
    end)

    it("does not error", function()
        assert.has_no.errors(function()
            vim.cmd('Mail')
        end)
    end)

    it("displays a clear error when himalaya is not installed", function()
        local message
        vim.fn.executable = function()
            return 0
        end
        vim.notify = function(notification)
            message = notification
        end

        vim.cmd('Mail')

        assert.equal('himalaya is not installed', message)
    end)

    it("completes partial subcommands", function()
        assert.same({ 'close' }, vim.fn.getcompletion('Mail cl', 'cmdline'))
    end)

    it("always offers new completion", function()
        assert.same({ 'new' }, vim.fn.getcompletion('Mail new', 'cmdline'))
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

    it("new opens an email buffer with recipient and subject fields", function()
        vim.cmd('Mail new')

        assert.same({ 'to: ', 'cc: ', 'bcc: ', 'subject: ' }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
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

    it("refresh refreshes the main menu buffer", function()
        vim.cmd('Mail')
        assert.is_true(vim.wait(1000, function()
            return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == 'Inbox'
        end))
        vim.bo.readonly = false
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'stale' })
        vim.bo.readonly = true

        vim.cmd('Mail refresh')

        assert.is_true(vim.wait(1000, function()
            return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == 'Inbox'
        end))
    end)

    it("offers refresh completion in main menu buffers", function()
        vim.cmd('Mail')

        assert.same({ 'refresh' }, vim.fn.getcompletion('Mail ref', 'cmdline'))
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

    local function open_first_message()
        open_inbox_mailbox()
        assert.is_true(vim.wait(1000, function()
            return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == '2026-01-01T00:00:00Z First example message'
        end))
        vim.api.nvim_feedkeys(vim.keycode('<CR>'), 'x', false)
        assert.is_true(vim.wait(1000, function()
            return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == 'From: Example Sender <sender@example.test>'
        end))
        vim.api.nvim_buf_set_lines(0, 2, 2, false, { 'Cc: Example Copy <copy@example.test>' })
    end

    it("completes subcommands", function()
        open_first_message()

        assert.same({ 'close', 'new', 'forward', 'reply', 'replyall' }, vim.fn.getcompletion('Mail ', 'cmdline'))
    end)

    it("offers reply completion in email buffers", function()
        open_first_message()

        assert.is_true(vim.tbl_contains(vim.fn.getcompletion('Mail ', 'cmdline'), 'reply'))
    end)

    it("offers replyall completion in email buffers", function()
        open_first_message()

        assert.is_true(vim.tbl_contains(vim.fn.getcompletion('Mail ', 'cmdline'), 'replyall'))
    end)

    it("offers forward completion in email buffers", function()
        open_first_message()

        assert.is_true(vim.tbl_contains(vim.fn.getcompletion('Mail ', 'cmdline'), 'forward'))
    end)

    it("offers send completion in email buffers with a reply section", function()
        open_first_message()
        vim.cmd('Mail reply')

        assert.is_true(vim.tbl_contains(vim.fn.getcompletion('Mail ', 'cmdline'), 'send'))
    end)

    it("offers send completion in email buffers with a replyall section", function()
        open_first_message()
        vim.cmd('Mail replyall')

        assert.is_true(vim.tbl_contains(vim.fn.getcompletion('Mail ', 'cmdline'), 'send'))
    end)

    it("offers send completion in email buffers with a forward section", function()
        open_first_message()
        vim.cmd('Mail forward')

        assert.is_true(vim.tbl_contains(vim.fn.getcompletion('Mail ', 'cmdline'), 'send'))
    end)

    it("offers send completion in new email buffers", function()
        vim.cmd('Mail new')

        assert.is_true(vim.tbl_contains(vim.fn.getcompletion('Mail ', 'cmdline'), 'send'))
    end)

    it("does not offer send completion in email buffers without a response section", function()
        open_first_message()

        assert.is_false(vim.tbl_contains(vim.fn.getcompletion('Mail ', 'cmdline'), 'send'))
    end)

    it("does not offer send completion in mailbox buffers", function()
        open_inbox_mailbox()

        assert.is_false(vim.tbl_contains(vim.fn.getcompletion('Mail ', 'cmdline'), 'send'))
    end)

    it("does not offer send completion in main menu buffers", function()
        vim.cmd('Mail')

        assert.is_false(vim.tbl_contains(vim.fn.getcompletion('Mail ', 'cmdline'), 'send'))
    end)

    it("does not offer refresh completion in email buffers", function()
        open_first_message()

        assert.is_false(vim.tbl_contains(vim.fn.getcompletion('Mail ', 'cmdline'), 'refresh'))
    end)

    it("does not offer refresh completion in new email buffers", function()
        vim.cmd('Mail new')

        assert.is_false(vim.tbl_contains(vim.fn.getcompletion('Mail ', 'cmdline'), 'refresh'))
    end)

    it("does not offer send completion in incomplete response sections", function()
        open_first_message()
        vim.api.nvim_buf_set_lines(0, -1, -1, false, { '', '', '--- Reply ---', 'to: recipient@example.test' })

        assert.is_false(vim.tbl_contains(vim.fn.getcompletion('Mail ', 'cmdline'), 'send'))
    end)

    it("reports ambiguous subcommand shorthands and their possible completions", function()
        local message
        open_first_message()
        vim.notify = function(notification)
            message = notification
        end

        vim.cmd('Mail r')

        assert.equal(':Mail r is ambiguous; possible completions: reply, replyall', message)
    end)

    it("does not offer reply completion in mailbox buffers", function()
        open_inbox_mailbox()

        assert.is_false(vim.tbl_contains(vim.fn.getcompletion('Mail ', 'cmdline'), 'reply'))
    end)

    it("does not offer replyall completion in mailbox buffers", function()
        open_inbox_mailbox()

        assert.is_false(vim.tbl_contains(vim.fn.getcompletion('Mail ', 'cmdline'), 'replyall'))
    end)

    it("does not offer forward completion in mailbox buffers", function()
        open_inbox_mailbox()

        assert.is_false(vim.tbl_contains(vim.fn.getcompletion('Mail ', 'cmdline'), 'forward'))
    end)

    it("does not offer reply completion in main menu buffers", function()
        vim.cmd('Mail')

        assert.is_false(vim.tbl_contains(vim.fn.getcompletion('Mail ', 'cmdline'), 'reply'))
    end)

    it("does not offer replyall completion in main menu buffers", function()
        vim.cmd('Mail')

        assert.is_false(vim.tbl_contains(vim.fn.getcompletion('Mail ', 'cmdline'), 'replyall'))
    end)

    it("does not offer forward completion in main menu buffers", function()
        vim.cmd('Mail')

        assert.is_false(vim.tbl_contains(vim.fn.getcompletion('Mail ', 'cmdline'), 'forward'))
    end)

    local function response_error(subcommand)
        local message
        vim.notify = function(notification)
            message = notification
        end
        vim.cmd('Mail ' .. subcommand)
        return message
    end

    it("rejects reply in mailbox buffers with a friendly error", function()
        open_inbox_mailbox()

        assert.equal(':Mail reply is only available in email buffers', response_error('reply'))
    end)

    it("rejects replyall in mailbox buffers with a friendly error", function()
        open_inbox_mailbox()

        assert.equal(':Mail replyall is only available in email buffers', response_error('replyall'))
    end)

    it("rejects forward in mailbox buffers with a friendly error", function()
        open_inbox_mailbox()

        assert.equal(':Mail forward is only available in email buffers', response_error('forward'))
    end)

    it("rejects send in mailbox buffers with a friendly error", function()
        open_inbox_mailbox()

        assert.equal(':Mail send is only available in email buffers', response_error('send'))
    end)

    it("rejects reply in main menu buffers with a friendly error", function()
        vim.cmd('Mail')

        assert.equal(':Mail reply is only available in email buffers', response_error('reply'))
    end)

    it("rejects replyall in main menu buffers with a friendly error", function()
        vim.cmd('Mail')

        assert.equal(':Mail replyall is only available in email buffers', response_error('replyall'))
    end)

    it("rejects forward in main menu buffers with a friendly error", function()
        vim.cmd('Mail')

        assert.equal(':Mail forward is only available in email buffers', response_error('forward'))
    end)

    it("rejects send in main menu buffers with a friendly error", function()
        vim.cmd('Mail')

        assert.equal(':Mail send is only available in email buffers', response_error('send'))
    end)

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

    it("refresh refreshes mailbox buffers", function()
        open_inbox_mailbox()
        assert.is_true(vim.wait(1000, function()
            return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == '2026-01-01T00:00:00Z First example message'
        end))
        vim.bo.readonly = false
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'stale' })
        vim.bo.readonly = true

        vim.cmd('Mail refresh')

        assert.is_true(vim.wait(1000, function()
            return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == '2026-01-01T00:00:00Z First example message'
        end))
    end)

    it("offers refresh completion in mailbox buffers", function()
        open_inbox_mailbox()

        assert.same({ 'refresh' }, vim.fn.getcompletion('Mail ref', 'cmdline'))
    end)

    it("reuses an active mailbox buffer from the main menu", function()
        local main_menu = open_inbox_mailbox()
        assert.is_true(vim.wait(1000, function()
            return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == '2026-01-01T00:00:00Z First example message'
        end))
        local expected = vim.api.nvim_get_current_buf()
        local count = #vim.api.nvim_list_bufs()

        vim.api.nvim_set_current_buf(main_menu)
        vim.api.nvim_feedkeys(vim.keycode('<CR>'), 'x', false)

        assert.equal(expected, vim.api.nvim_get_current_buf())
        assert.equal(count, #vim.api.nvim_list_bufs())
    end)

    it("reuses a hidden mailbox buffer from the main menu", function()
        open_inbox_mailbox()
        assert.is_true(vim.wait(1000, function()
            return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == '2026-01-01T00:00:00Z First example message'
        end))
        local expected = vim.api.nvim_get_current_buf()

        vim.cmd('enew')
        vim.cmd('Mail')
        assert.is_true(vim.wait(1000, function()
            return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == 'Inbox'
        end))
        local count = #vim.api.nvim_list_bufs()

        vim.api.nvim_feedkeys(vim.keycode('<CR>'), 'x', false)

        assert.equal(expected, vim.api.nvim_get_current_buf())
        assert.equal(count, #vim.api.nvim_list_bufs())
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

    it("reply appends a Reply header to email buffers", function()
        open_first_message()

        vim.cmd('Mail reply')

        assert.same({
            '',
            '',
            '--- Reply ---',
            'to: Example Sender <sender@example.test>',
            'cc: Example Copy <copy@example.test>',
            'bcc: ',
            'subject: Re: First example message',
            '',
        }, vim.api.nvim_buf_get_lines(0, -9, -1, false))
    end)

    it("replyall appends a Reply All header to email buffers", function()
        open_first_message()

        vim.cmd('Mail replyall')

        assert.same({
            '',
            '',
            '--- Reply All ---',
            'to: Example Sender <sender@example.test>',
            'cc: Example Copy <copy@example.test>',
            'bcc: ',
            'subject: Re: First example message',
            '',
        }, vim.api.nvim_buf_get_lines(0, -9, -1, false))
    end)

    it("forward appends a Forward header to email buffers", function()
        open_first_message()

        vim.cmd('Mail forward')

        assert.same({
            '',
            '',
            '--- Forward ---',
            'to: Example Sender <sender@example.test>',
            'cc: Example Copy <copy@example.test>',
            'bcc: ',
            'subject: Fwd: First example message',
            '',
        }, vim.api.nvim_buf_get_lines(0, -9, -1, false))
    end)

    it("send sends responses to their To, Cc, and Bcc recipients", function()
        local message
        open_first_message()
        vim.cmd('Mail reply')
        vim.api.nvim_buf_set_lines(0, -7, -1, false, {
            '--- Reply ---',
            'to: Example Sender <sender@example.test>',
            'cc: Example Copy <copy@example.test>',
            'bcc: Example Blind Copy <blind-copy@example.test>',
            'subject: Re: First example message',
            '',
            'Thanks.',
        })
        vim.notify = function(notification)
            message = notification
        end

        vim.cmd('Mail send')

        assert.is_true(vim.wait(1000, function()
            return message ~= nil
        end))
        assert.equal('Message successfully sent', message)
    end)

    it("send shows successful new messages in :messages", function()
        vim.cmd('Mail new')
        vim.api.nvim_buf_set_lines(0, 0, -1, false, {
            'to: Example Sender <sender@example.test>',
            'cc: Example Copy <copy@example.test>',
            'bcc: Example Blind Copy <blind-copy@example.test>',
            'subject: Re: First example message',
            'attach: ',
            '',
            'Thanks.',
        })

        vim.cmd('Mail send')

        assert.is_true(vim.wait(1000, function()
            return vim.api.nvim_exec2('messages', { output = true }).output:find('Message successfully sent', 1, true) ~= nil
        end))
    end)

    it("send closes new email buffers after successful sends", function()
        vim.cmd('Mail new')
        local email = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_set_lines(email, 0, -1, false, {
            'to: Example Sender <sender@example.test>',
            'cc: Example Copy <copy@example.test>',
            'bcc: Example Blind Copy <blind-copy@example.test>',
            'subject: Re: First example message',
            'attach: ',
            '',
            'Thanks.',
        })

        vim.cmd('Mail send')

        assert.is_true(vim.wait(1000, function()
            return not vim.api.nvim_buf_is_valid(email)
        end))
    end)

    it("send uses the configured email address as the From header", function()
        local command
        vim.cmd('Mail new')
        vim.api.nvim_buf_set_lines(0, 0, -1, false, {
            'to: recipient@example.test',
            'cc: ',
            'bcc: ',
            'subject: Example subject',
            'attach: ',
            '',
            'Example body.',
        })
        vim.system = function(args, _, callback)
            command = args
            vim.schedule(function()
                callback({ code = 0, stdout = 'Message successfully sent\n', stderr = '' })
            end)
        end

        vim.cmd('Mail send')

        assert.is_true(vim.wait(1000, function()
            return command ~= nil
        end))
        assert.same({
            'himalaya', 'message', 'compose',
            '--from', 'example@gmail.com',
            '--to', 'recipient@example.test',
            '--subject', 'Example subject',
            '--body', 'Example body.',
            '--send',
        }, command)
    end)

    it("send reports the failed himalaya command, stdout, and stderr when sending fails", function()
        local message
        local command
        open_first_message()
        vim.cmd('Mail reply')
        vim.system = function(args, _, callback)
            command = args
            vim.schedule(function()
                callback({
                    code = 1,
                    stdout = 'Himalaya stdout\n',
                    stderr = 'Himalaya stderr\n',
                })
            end)
        end
        vim.notify = function(notification)
            message = notification
        end

        vim.cmd('Mail send')

        assert.is_true(vim.wait(1000, function()
            return message ~= nil
        end))
        assert.equal(
            table.concat(command, ' ') .. '\nHimalaya stdout\nHimalaya stderr\n',
            message
        )
    end)

    it("send attaches the file from the attach field", function()
        local command
        open_first_message()
        vim.cmd('Mail reply')
        vim.api.nvim_buf_set_lines(0, -2, -2, false, { 'attach: /bin/bash' })
        vim.system = function(args, _, callback)
            command = args
            vim.schedule(function()
                callback({ code = 0, stdout = 'Message successfully sent\n', stderr = '' })
            end)
        end

        vim.cmd('Mail send')

        assert.is_true(vim.wait(1000, function()
            return command ~= nil
        end))
        assert.is_true(vim.tbl_contains(command, '--attach'))
        assert.is_true(vim.tbl_contains(command, '/bin/bash'))
    end)

    it("send supports repeated recipient and attachment fields", function()
        local command
        open_first_message()
        vim.cmd('Mail reply')
        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        local response_start
        for index, line in ipairs(lines) do
            if line == '--- Reply ---' then
                response_start = index
            end
        end
        vim.api.nvim_buf_set_lines(0, response_start - 1, -1, false, {
            '--- Reply ---',
            'to: first-to@example.test',
            'to: second-to@example.test',
            'cc: first-cc@example.test',
            'cc: second-cc@example.test',
            'bcc: first-bcc@example.test',
            'bcc: second-bcc@example.test',
            'subject: Re: First example message',
            'attach: /bin/bash',
            'attach: /bin/sh',
            '',
            'Thanks.',
        })
        vim.system = function(args, _, callback)
            command = args
            vim.schedule(function()
                callback({ code = 0, stdout = 'Message successfully sent\n', stderr = '' })
            end)
        end

        vim.cmd('Mail send')

        assert.is_true(vim.wait(1000, function()
            return command ~= nil
        end))
        assert.same({
            'himalaya', 'message', 'compose',
            '--from', 'example@gmail.com',
            '--to', 'first-to@example.test',
            '--to', 'second-to@example.test',
            '--cc', 'first-cc@example.test',
            '--cc', 'second-cc@example.test',
            '--bcc', 'first-bcc@example.test',
            '--bcc', 'second-bcc@example.test',
            '--subject', 'Re: First example message',
            '--attach', '/bin/bash',
            '--attach', '/bin/sh',
            '--body', 'Thanks.',
            '--send',
        }, command)
    end)

    it("attaches a ranged file path to the last compose buffer", function()
        open_first_message()
        vim.cmd('Mail reply')
        local email = vim.api.nvim_get_current_buf()
        local source = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_buf_set_lines(source, 0, -1, false, { '/bin/bash' })
        vim.api.nvim_set_current_buf(source)

        vim.cmd('1,1Mail')

        assert.is_true(vim.tbl_contains(vim.api.nvim_buf_get_lines(email, 0, -1, false), 'attach: /bin/bash'))
    end)

    it("resolves relative attachment paths to absolute paths", function()
        vim.cmd('Mail new')
        local email = vim.api.nvim_get_current_buf()
        local source = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_buf_set_lines(source, 0, -1, false, { 'tests/message.txt' })
        vim.api.nvim_set_current_buf(source)

        vim.cmd('1,1Mail')

        assert.is_true(vim.tbl_contains(
            vim.api.nvim_buf_get_lines(email, 0, -1, false),
            'attach: ' .. vim.fn.getcwd() .. '/tests/message.txt'
        ))
    end)

    it("attaches a path selected from a terminal after opening a new email", function()
        vim.cmd('Mail new')
        local email = vim.api.nvim_get_current_buf()
        vim.cmd("terminal printf '/bin/bash\\n'")
        assert.is_true(vim.wait(1000, function()
            return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == '/bin/bash'
        end))

        vim.cmd('1,1Mail')

        assert.is_true(vim.tbl_contains(vim.api.nvim_buf_get_lines(email, 0, -1, false), 'attach: /bin/bash'))
    end)

    it("keeps the attachment field for subsequent terminal selections", function()
        vim.cmd('Mail new')
        local email = vim.api.nvim_get_current_buf()
        vim.cmd('split')
        vim.cmd("terminal printf '/bin/bash\\n/bin/sh\\n'")
        assert.is_true(vim.wait(1000, function()
            return vim.api.nvim_buf_get_lines(0, 0, 2, false)[2] == '/bin/sh'
        end))

        vim.cmd('1,1Mail')
        vim.cmd('2,2Mail')

        assert.same({ 'attach: /bin/bash', 'attach: /bin/sh' }, vim.tbl_filter(function(line)
            return vim.startswith(line, 'attach:')
        end, vim.api.nvim_buf_get_lines(email, 0, -1, false)))
    end)

    it("opens a new email when attaching without a compose buffer", function()
        local source = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_buf_set_lines(source, 0, -1, false, { '/bin/bash' })
        vim.api.nvim_set_current_buf(source)

        vim.cmd('1,1Mail')

        assert.not_equal(source, vim.api.nvim_get_current_buf())
        assert.is_true(vim.tbl_contains(vim.api.nvim_buf_get_lines(0, 0, -1, false), 'attach: /bin/bash'))
    end)

    it("rejects ranged attachment paths that are not files", function()
        local message
        local level
        local source = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_buf_set_lines(source, 0, -1, false, { '/not/a/real/vimalaya-attachment' })
        vim.api.nvim_set_current_buf(source)
        vim.notify = function(notification, notification_level)
            message = notification
            level = notification_level
        end

        vim.cmd('1,1Mail')

        assert.equal(':Mail cannot attach /not/a/real/vimalaya-attachment: not a file', message)
        assert.equal(vim.log.levels.ERROR, level)
    end)

    it("attaches multiple ranged file paths as separate fields", function()
        open_first_message()
        vim.cmd('Mail reply')
        local email = vim.api.nvim_get_current_buf()
        local source = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_buf_set_lines(source, 0, -1, false, { '/bin/bash', '/bin/sh' })
        vim.api.nvim_set_current_buf(source)

        vim.cmd('1,2Mail')

        local attachments = vim.tbl_filter(function(line)
            return vim.startswith(line, 'attach:')
        end, vim.api.nvim_buf_get_lines(email, 0, -1, false))
        assert.same({ 'attach: /bin/bash', 'attach: /bin/sh' }, attachments)
    end)

    it("ranged new opens a new email for selected attachments", function()
        open_first_message()
        vim.cmd('Mail reply')
        local previous = vim.api.nvim_get_current_buf()
        local source = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_buf_set_lines(source, 0, -1, false, { '/bin/bash', '/bin/sh' })
        vim.api.nvim_set_current_buf(source)

        vim.cmd('1,2Mail new')

        assert.not_equal(source, vim.api.nvim_get_current_buf())
        assert.not_equal(previous, vim.api.nvim_get_current_buf())
        assert.same({
            'to: ',
            'cc: ',
            'bcc: ',
            'subject: ',
            'attach: /bin/bash',
            'attach: /bin/sh',
        }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
    end)

    local function assert_send_removes_response(kind)
        open_first_message()
        local original = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        vim.cmd('Mail ' .. kind)
        vim.system = function(_, _, callback)
            vim.schedule(function()
                callback({ code = 0, stdout = 'Message successfully sent\n', stderr = '' })
            end)
        end

        vim.cmd('Mail send')

        assert.is_true(vim.wait(1000, function()
            return vim.deep_equal(original, vim.api.nvim_buf_get_lines(0, 0, -1, false))
        end))
    end

    it("send removes reply sections after successful sends", function()
        assert_send_removes_response('reply')
    end)

    it("send removes replyall sections after successful sends", function()
        assert_send_removes_response('replyall')
    end)

    it("send removes forward sections after successful sends", function()
        assert_send_removes_response('forward')
    end)
end)
