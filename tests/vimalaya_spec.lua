local busted = require("plenary.busted")
local spy = require("luassert.spy")
local describe = busted.describe
local it = busted.it
local before_each = busted.before_each
local after_each = busted.after_each

local header_docs = require('vimalaya').header_docs

describe(":Mail", function()
    local executable
    local executable_mocks
    local last_system_opts
    local download_dir
    local notify
    local system

    before_each(function()
        executable = vim.fn.executable
        notify = vim.notify
        system = vim.system
        download_dir = vim.fn.tempname()
        vim.fn.mkdir(download_dir, 'p')
        executable_mocks = {
            ['clamscan'] = function() return { code = 0, stdout = '', stderr = '' } end,
            ['himalaya mailbox list --json'] = 'tests/mailboxes.json',
            ['himalaya envelope list --mailbox Inbox --json --page-size 200'] = 'tests/envelopes.json',
            ['himalaya envelope list --mailbox Inbox --json --page-size 0'] = 'tests/envelopes.json',
            ['himalaya message read --mailbox Inbox 1'] = 'tests/message.txt',
            ['himalaya message read --mailbox Inbox 2'] = 'tests/message.txt',
            ['himalaya message compose'] = 'tests/send-suceeded.txt',
            ['himalaya attachment list --mailbox Inbox --json 1'] = 'tests/attachments-empty.json',
            ['himalaya attachment list --mailbox Inbox --json 2'] = 'tests/attachments.json',
            ['himalaya attachment download --mailbox Inbox --json 2 1'] = function(command)
                local temporary_dir = download_dir
                for index, argument in ipairs(command) do
                    if argument == '--dir' then
                        temporary_dir = command[index + 1]
                    end
                end
                local path = temporary_dir .. '/invite.ics'
                vim.fn.writefile(vim.fn.readfile('tests/invite.ics', 'b'), path, 'b')
                return {
                    code = 0,
                    stdout = vim.json.encode({ attachments = { { path = path } } }),
                    stderr = '',
                }
            end,
        }
        vim.system = function(command, opts, callback)
            last_system_opts = opts
            local command_string = table.concat(command, ' ')
            local lookup_command = vim.deepcopy(command)
            if command[1] == 'himalaya' and command[2] == 'attachment' and command[3] == 'download' then
                for index, argument in ipairs(lookup_command) do
                    if argument == '--dir' then
                        table.remove(lookup_command, index)
                        table.remove(lookup_command, index)
                        break
                    end
                end
            end
            local mock = executable_mocks[table.concat(lookup_command, ' ')]
                or executable_mocks[command[1]]
            if command[1] == 'himalaya' and command[2] == 'message' and command[3] == 'compose' then
                mock = mock or executable_mocks['himalaya message compose']
            end
            assert.is_not_nil(mock, 'unexpected command: ' .. command_string)

            local result
            if type(mock) == 'function' then
                result = mock(command)
            else
                result = {
                    code = 0,
                    stdout = table.concat(vim.fn.readfile(mock), '\n'),
                    stderr = '',
                }
            end

            if result == nil then
                return
            end
            if result.delay then
                vim.defer_fn(function()
                    callback(result)
                end, result.delay)
                return
            end
            vim.schedule(function()
                callback(result)
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
        vim.fn.delete(download_dir, 'rf')
        vim.fn.delete(vim.fn.getcwd() .. '/invite.ics')
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
            return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == '2026-01-01 00:00 First example message'
        end))
        vim.api.nvim_feedkeys(vim.keycode('<CR>'), 'x', false)
        assert.is_true(vim.wait(1000, function()
            return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == 'From: Example Sender <sender@example.test>'
        end))
        vim.api.nvim_buf_set_lines(0, 2, 2, false, { 'Cc: Example Copy <copy@example.test>' })
    end

    local preview_command = 'himalaya envelope list --mailbox Inbox --json --page-size 200'
    local full_command = 'himalaya envelope list --mailbox Inbox --json --page-size 0'

    local function envelope_result(count, delay)
        local envelopes = {}
        for id = 1, count do
            table.insert(envelopes, {
                id = tostring(id),
                subject = 'Message ' .. id,
                date = '2026-01-01T00:00:00Z',
            })
        end
        return {
            code = 0,
            stdout = vim.json.encode({ envelopes = envelopes }),
            stderr = '',
            delay = delay,
        }
    end

    local function mock_envelopes(command, count, delay)
        executable_mocks[command] = function()
            return envelope_result(count, delay)
        end
    end

    local function mock_envelope_list(envelopes)
        local result = { code = 0, stdout = vim.json.encode({ envelopes = envelopes }), stderr = '' }
        executable_mocks[preview_command] = function()
            return result
        end
        executable_mocks[full_command] = function()
            return result
        end
    end

    local function listed_envelope_lines()
        assert.is_true(vim.wait(1000, function()
            return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] ~= ''
        end))
        return vim.api.nvim_buf_get_lines(0, 0, -1, false)
    end

    it("requests a preview of two hundred envelopes", function()
        local command
        executable_mocks[preview_command] = function(args)
            command = args
            return envelope_result(3)
        end
        mock_envelopes(full_command, 3)
        open_inbox_mailbox()

        assert.is_true(vim.wait(1000, function()
            return command ~= nil
        end))
        assert.same({
            'himalaya', 'envelope', 'list', '--mailbox', 'Inbox', '--json', '--page-size', '200',
        }, command)
    end)

    it("requests every envelope", function()
        local command
        mock_envelopes(preview_command, 3)
        executable_mocks[full_command] = function(args)
            command = args
            return envelope_result(3)
        end
        open_inbox_mailbox()

        assert.is_true(vim.wait(1000, function()
            return command ~= nil
        end))
        assert.same({
            'himalaya', 'envelope', 'list', '--mailbox', 'Inbox', '--json', '--page-size', '0',
        }, command)
    end)

    it("lists the preview while every envelope is still loading", function()
        mock_envelopes(preview_command, 200)
        executable_mocks[full_command] = function() end
        open_inbox_mailbox()

        assert.is_true(vim.wait(1000, function()
            return vim.api.nvim_buf_line_count(0) == 200
        end))
    end)

    it("replaces the preview with every envelope", function()
        mock_envelopes(preview_command, 200)
        mock_envelopes(full_command, 203)
        open_inbox_mailbox()

        assert.is_true(vim.wait(1000, function()
            return vim.api.nvim_buf_line_count(0) == 203
        end))
        assert.equal('2026-01-01 00:00 Message 203', vim.api.nvim_buf_get_lines(0, 202, 203, false)[1])
    end)

    it("keeps every envelope when the preview arrives last", function()
        mock_envelopes(preview_command, 200, 50)
        mock_envelopes(full_command, 203)
        open_inbox_mailbox()

        assert.is_true(vim.wait(1000, function()
            return vim.api.nvim_buf_line_count(0) == 203
        end))
        vim.wait(100)
        assert.equal(203, vim.api.nvim_buf_line_count(0))
    end)

    it("opens the message of an envelope outside the preview", function()
        mock_envelopes(preview_command, 200)
        mock_envelopes(full_command, 203)
        executable_mocks['himalaya message read --mailbox Inbox 203'] = 'tests/message.txt'
        open_inbox_mailbox()
        assert.is_true(vim.wait(1000, function()
            return vim.api.nvim_buf_line_count(0) == 203
        end))
        vim.api.nvim_win_set_cursor(0, { 203, 0 })
        vim.api.nvim_feedkeys(vim.keycode('<CR>'), 'x', false)

        assert.is_true(vim.wait(1000, function()
            return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1]
                == 'From: Example Sender <sender@example.test>'
        end))
    end)

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
            return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == '2026-01-01 00:00 First example message'
        end))
        assert.same({
            '2026-01-01 00:00 First example message',
            '2026-01-02 00:00 Second example message',
            '2026-01-03 00:00 Third example message',
        }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
    end)

    it("displays envelope dates in the local timezone", function()
        assert.equal('2026-06-15 07:00', require('vimalaya')._format_envelope_date('2026-06-15T12:00:00+05:00'))
    end)

    it("aligns envelope subjects at the same column", function()
        open_inbox_mailbox()

        assert.is_true(vim.wait(1000, function()
            return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == '2026-01-01 00:00 First example message'
        end))
        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        local first = lines[1]:find('First')
        assert.equal(first, lines[2]:find('Second'))
        assert.equal(first, lines[3]:find('Third'))
    end)

    it("lists envelopes without a date", function()
        mock_envelope_list({
            { id = '1', subject = 'Dated message', date = '2026-01-01T00:00:00Z' },
            { id = '2', subject = 'Undated message', date = vim.NIL },
        })
        open_inbox_mailbox()

        assert.same({
            '2026-01-01 00:00 Dated message',
            '                 Undated message',
        }, listed_envelope_lines())
    end)

    it("lists envelopes without a date when no envelope has a date", function()
        mock_envelope_list({
            { id = '1', subject = 'Undated message', date = vim.NIL },
        })
        open_inbox_mailbox()

        assert.same({ 'Undated message' }, listed_envelope_lines())
    end)

    it("refresh refreshes mailbox buffers", function()
        open_inbox_mailbox()
        assert.is_true(vim.wait(1000, function()
            return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == '2026-01-01 00:00 First example message'
        end))
        vim.bo.readonly = false
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'stale' })
        vim.bo.readonly = true

        vim.cmd('Mail refresh')

        assert.is_true(vim.wait(1000, function()
            return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == '2026-01-01 00:00 First example message'
        end))
    end)

    it("offers refresh completion in mailbox buffers", function()
        open_inbox_mailbox()

        assert.same({ 'refresh' }, vim.fn.getcompletion('Mail ref', 'cmdline'))
    end)

    it("reuses an active mailbox buffer from the main menu", function()
        local main_menu = open_inbox_mailbox()
        assert.is_true(vim.wait(1000, function()
            return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == '2026-01-01 00:00 First example message'
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
            return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == '2026-01-01 00:00 First example message'
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
            return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == '2026-01-01 00:00 First example message'
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
            return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == '2026-01-01 00:00 First example message'
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
            return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == '2026-01-01 00:00 First example message'
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
            return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == '2026-01-01 00:00 First example message'
        end))

        vim.api.nvim_feedkeys(vim.keycode('<CR>'), 'x', false)
        assert.is_true(vim.wait(1000, function()
            return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == 'From: Example Sender <sender@example.test>'
        end))

        assert.is_false(vim.bo.readonly)
    end)

    local function open_message_with_attachments()
        require('vimalaya').open_message('Inbox', '2', 'Message with attachments')
        assert.is_true(vim.wait(1000, function()
            return vim.tbl_contains(vim.api.nvim_buf_get_lines(0, 0, -1, false), 'attachments:')
        end))
    end

    it("lists attachments at the bottom of email buffers", function()
        open_message_with_attachments()

        assert.same({
            'attachments:',
            '  filename: invite.ics',
            '    mime: text/calendar',
            '    size: 842',
            '  filename: agenda.pdf',
            '    mime: application/pdf',
            '    size: 839',
        }, vim.api.nvim_buf_get_lines(0, 9, -1, false))
    end)

    it("displays the path of a downloaded attachment", function()
        open_message_with_attachments()
        vim.api.nvim_win_set_cursor(0, { 11, 0 })

        vim.api.nvim_feedkeys(vim.keycode('<CR>'), 'x', false)

        assert.is_true(vim.wait(1000, function()
            return vim.api.nvim_get_current_line()
                == '  filename: invite.ics ' .. vim.fn.getcwd() .. '/invite.ics'
        end))
    end)

    it("downloads an attachment", function()
        local temporary_path
        executable_mocks['himalaya attachment download --mailbox Inbox --json 2 1'] = function(command)
            local temporary_dir = download_dir
            for index, argument in ipairs(command) do
                if argument == '--dir' then
                    temporary_dir = command[index + 1]
                end
            end
            temporary_path = temporary_dir .. '/invite.ics'
            vim.fn.writefile(vim.fn.readfile('tests/invite.ics', 'b'), temporary_path, 'b')
            return {
                code = 0,
                stdout = vim.json.encode({ attachments = { { path = temporary_path } } }),
                stderr = '',
            }
        end
        open_message_with_attachments()
        vim.api.nvim_win_set_cursor(0, { 11, 0 })

        vim.api.nvim_feedkeys(vim.keycode('<CR>'), 'x', false)

        assert.is_true(vim.wait(1000, function()
            return vim.fn.filereadable(vim.fn.getcwd() .. '/invite.ics') == 1
        end))
        assert.same(
            vim.fn.readfile('tests/invite.ics', 'b'),
            vim.fn.readfile(vim.fn.getcwd() .. '/invite.ics', 'b')
        )
    end)

    it("scans downloaded attachments with ClamAV", function()
        local scanned_path
        executable_mocks['clamscan'] = function(command)
            scanned_path = command[2]
            return { code = 0, stdout = '', stderr = '' }
        end
        open_message_with_attachments()
        vim.api.nvim_win_set_cursor(0, { 11, 0 })

        vim.api.nvim_feedkeys(vim.keycode('<CR>'), 'x', false)

        assert.is_true(vim.wait(1000, function()
            return scanned_path ~= nil
        end))
        assert.is_true(vim.endswith(scanned_path, '/invite.ics'))
        assert.is_false(vim.startswith(scanned_path, download_dir))
    end)

    it("deletes attachments when ClamAV detects a virus", function()
        local infected_path
        executable_mocks['clamscan'] = function(command)
            infected_path = command[2]
            return { code = 1, stdout = 'Eicar-Test-Signature FOUND\n', stderr = '' }
        end
        open_message_with_attachments()
        vim.api.nvim_win_set_cursor(0, { 11, 0 })

        vim.api.nvim_feedkeys(vim.keycode('<CR>'), 'x', false)

        assert.is_true(vim.wait(1000, function()
            return infected_path ~= nil and vim.fn.filereadable(infected_path) == 0
        end))
    end)

    it("does not display a download path when ClamAV detects a virus", function()
        local scanned = false
        executable_mocks['clamscan'] = function()
            scanned = true
            return { code = 1, stdout = 'Eicar-Test-Signature FOUND\n', stderr = '' }
        end
        open_message_with_attachments()
        vim.api.nvim_win_set_cursor(0, { 11, 0 })

        vim.api.nvim_feedkeys(vim.keycode('<CR>'), 'x', false)
        assert.is_true(vim.wait(1000, function()
            return scanned
        end))

        assert.equal('  filename: invite.ics VIRUS DETECTED - FILE DELETED', vim.api.nvim_get_current_line())
    end)

    it("displays downloading while an attachment downloads", function()
        open_message_with_attachments()
        vim.api.nvim_win_set_cursor(0, { 11, 0 })
        vim.system = function() end

        vim.api.nvim_feedkeys(vim.keycode('<CR>'), 'x', false)

        assert.equal('  filename: invite.ics downloading', vim.api.nvim_get_current_line())
    end)

    it("displays scanning for viruses while an attachment is scanned", function()
        local download = vim.system
        vim.system = function(command, opts, callback)
            if command[1] == 'clamscan' then
                return
            end
            return download(command, opts, callback)
        end
        open_message_with_attachments()
        vim.api.nvim_win_set_cursor(0, { 11, 0 })

        vim.api.nvim_feedkeys(vim.keycode('<CR>'), 'x', false)

        assert.is_true(vim.wait(1000, function()
            return vim.api.nvim_get_current_line() == '  filename: invite.ics scanning for viruses'
        end))
    end)

    it("displays scanning for viruses failed when the ClamAV scan fails", function()
        executable_mocks['clamscan'] = function()
            return { code = 2, stdout = '', stderr = 'ClamAV stderr\n' }
        end
        vim.notify = function() end
        open_message_with_attachments()
        vim.api.nvim_win_set_cursor(0, { 11, 0 })

        vim.api.nvim_feedkeys(vim.keycode('<CR>'), 'x', false)

        assert.is_true(vim.wait(1000, function()
            return vim.api.nvim_get_current_line() == '  filename: invite.ics scanning for viruses failed'
        end))
    end)

    it("reports the failed ClamAV scan command, stdout, and stderr", function()
        local message
        local command
        executable_mocks['clamscan'] = function(args)
            command = args
            return { code = 2, stdout = 'ClamAV stdout\n', stderr = 'ClamAV stderr\n' }
        end
        vim.notify = function(notification)
            message = notification
        end
        open_message_with_attachments()
        vim.api.nvim_win_set_cursor(0, { 11, 0 })

        vim.api.nvim_feedkeys(vim.keycode('<CR>'), 'x', false)

        assert.is_true(vim.wait(1000, function()
            return message ~= nil
        end))
        assert.equal(
            'vimalaya command failed:\n```sh\n'
                .. table.concat(command, ' ') .. '\n```'
                .. '\n```stdout\nClamAV stdout\n```\n```stderr\nClamAV stderr\n```',
            message
        )
    end)

    it("warns when ClamAV is not installed instead of downloading attachments", function()
        local message
        vim.fn.executable = function()
            return 0
        end
        vim.notify = function(notification)
            message = notification
        end
        open_message_with_attachments()
        vim.api.nvim_win_set_cursor(0, { 11, 0 })

        vim.api.nvim_feedkeys(vim.keycode('<CR>'), 'x', false)

        assert.equal('ClamAV antivirus is not installed; attachments cannot be downloaded', message)
    end)

    it("does not display an attachment path when downloading fails", function()
        local finished = false
        executable_mocks['himalaya attachment download --mailbox Inbox --json 2 1'] = function()
            return { code = 1, stdout = 'Himalaya stdout\n', stderr = 'Himalaya stderr\n' }
        end
        vim.notify = function()
            finished = true
        end
        open_message_with_attachments()
        vim.api.nvim_win_set_cursor(0, { 11, 0 })

        vim.api.nvim_feedkeys(vim.keycode('<CR>'), 'x', false)
        assert.is_true(vim.wait(1000, function()
            return finished
        end))

        assert.equal('  filename: invite.ics', vim.api.nvim_get_current_line())
    end)

    it("reports the failed attachment download command, stdout, and stderr", function()
        local message
        local command
        executable_mocks['himalaya attachment download --mailbox Inbox --json 2 1'] = function(args)
            command = args
            return { code = 1, stdout = 'Himalaya stdout\n', stderr = 'Himalaya stderr\n' }
        end
        vim.notify = function(notification)
            message = notification
        end
        open_message_with_attachments()
        vim.api.nvim_win_set_cursor(0, { 11, 0 })

        vim.api.nvim_feedkeys(vim.keycode('<CR>'), 'x', false)

        assert.is_true(vim.wait(1000, function()
            return message ~= nil
        end))
        assert.equal(
            'vimalaya command failed:\n```sh\n'
                .. table.concat(command, ' ') .. '\n```'
                .. '\n```stdout\nHimalaya stdout\n```\n```stderr\nHimalaya stderr\n```',
            message
        )
    end)

    it("reports the failed mailbox list command, stdout, and stderr", function()
        local message
        local command
        executable_mocks['himalaya mailbox list --json'] = function(args)
            command = args
            return { code = 1, stdout = 'Himalaya stdout\n', stderr = 'Himalaya stderr\n' }
        end
        vim.notify = function(notification)
            message = notification
        end
        vim.cmd('Mail')

        assert.is_true(vim.wait(1000, function()
            return message ~= nil
        end))
        assert.equal(
            'vimalaya command failed:\n```sh\n'
                .. table.concat(command, ' ') .. '\n```'
                .. '\n```stdout\nHimalaya stdout\n```\n```stderr\nHimalaya stderr\n```',
            message
        )
    end)

    it("reports the failed envelope list command, stdout, and stderr", function()
        local message
        local command
        executable_mocks['himalaya envelope list --mailbox Inbox --json --page-size 200'] = function(args)
            command = args
            return { code = 1, stdout = 'Himalaya stdout\n', stderr = 'Himalaya stderr\n' }
        end
        vim.notify = function(notification)
            message = notification
        end
        open_inbox_mailbox()

        assert.is_true(vim.wait(1000, function()
            return message ~= nil
        end))
        assert.equal(
            'vimalaya command failed:\n```sh\n'
                .. table.concat(command, ' ') .. '\n```'
                .. '\n```stdout\nHimalaya stdout\n```\n```stderr\nHimalaya stderr\n```',
            message
        )
    end)

    it("reports the failed message read command, stdout, and stderr", function()
        local message
        local command
        executable_mocks['himalaya message read --mailbox Inbox 1'] = function(args)
            command = args
            return { code = 1, stdout = 'Himalaya stdout\n', stderr = 'Himalaya stderr\n' }
        end
        vim.notify = function(notification)
            message = notification
        end
        open_inbox_mailbox()
        assert.is_true(vim.wait(1000, function()
            return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == '2026-01-01 00:00 First example message'
        end))
        vim.api.nvim_feedkeys(vim.keycode('<CR>'), 'x', false)

        assert.is_true(vim.wait(1000, function()
            return message ~= nil
        end))
        assert.equal(
            'vimalaya command failed:\n```sh\n'
                .. table.concat(command, ' ') .. '\n```'
                .. '\n```stdout\nHimalaya stdout\n```\n```stderr\nHimalaya stderr\n```',
            message
        )
    end)

    it("reports the failed attachment list command, stdout, and stderr", function()
        local message
        local command
        executable_mocks['himalaya attachment list --mailbox Inbox --json 2'] = function(args)
            command = args
            return { code = 1, stdout = 'Himalaya stdout\n', stderr = 'Himalaya stderr\n' }
        end
        vim.notify = function(notification)
            message = notification
        end
        require('vimalaya').open_message('Inbox', '2', 'Message with attachments')

        assert.is_true(vim.wait(1000, function()
            return message ~= nil
        end))
        assert.equal(
            'vimalaya command failed:\n```sh\n'
                .. table.concat(command, ' ') .. '\n```'
                .. '\n```stdout\nHimalaya stdout\n```\n```stderr\nHimalaya stderr\n```',
            message
        )
    end)

    it("restores an email after deleting its buffer", function()
        open_inbox_mailbox()
        assert.is_true(vim.wait(1000, function()
            return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == '2026-01-01 00:00 First example message'
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
            return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == '2026-01-01 00:00 First example message'
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
            return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == '2026-01-01 00:00 First example message'
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

    it("reply expands multiple source Cc headers into separate cc lines", function()
        open_first_message()
        vim.api.nvim_buf_set_lines(0, 3, 3, false, { 'Cc: Second Copy <second-copy@example.test>' })

        vim.cmd('Mail reply')

        assert.same({
            '',
            '',
            '--- Reply ---',
            'to: Example Sender <sender@example.test>',
            'cc: Example Copy <copy@example.test>',
            'cc: Second Copy <second-copy@example.test>',
            'bcc: ',
            'subject: Re: First example message',
            '',
        }, vim.api.nvim_buf_get_lines(0, -10, -1, false))
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
        executable_mocks['himalaya message compose'] = function(args)
            command = args
            return { code = 0, stdout = 'Message successfully sent\n', stderr = '' }
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

    it("send omits the body flag when the composed body is empty", function()
        local command
        vim.cmd('Mail new')
        vim.api.nvim_buf_set_lines(0, 0, -1, false, {
            'to: recipient@example.test',
            'cc: ',
            'bcc: ',
            'subject: Example subject',
            'attach: ',
            '',
        })
        executable_mocks['himalaya message compose'] = function(args)
            command = args
            return { code = 0, stdout = 'Message successfully sent\n', stderr = '' }
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
            '--send',
        }, command)
    end)

    it("send closes stdin so himalaya does not block reading the body", function()
        local command
        vim.cmd('Mail new')
        vim.api.nvim_buf_set_lines(0, 0, -1, false, {
            'to: recipient@example.test',
            'cc: ',
            'bcc: ',
            'subject: Example subject',
            'attach: ',
            '',
        })
        executable_mocks['himalaya message compose'] = function(args)
            command = args
            return { code = 0, stdout = 'Message successfully sent\n', stderr = '' }
        end

        vim.cmd('Mail send')

        assert.is_true(vim.wait(1000, function()
            return command ~= nil
        end))
        assert.equal(false, last_system_opts.stdin)
    end)

    it("send reports the failed himalaya command, stdout, and stderr when sending fails", function()
        local message
        local command
        open_first_message()
        vim.cmd('Mail reply')
        executable_mocks['himalaya message compose'] = function(args)
            command = args
            return {
                code = 1,
                stdout = 'Himalaya stdout\n',
                stderr = 'Himalaya stderr\n',
            }
        end
        vim.notify = function(notification)
            message = notification
        end

        vim.cmd('Mail send')

        assert.is_true(vim.wait(1000, function()
            return message ~= nil
        end))
        assert.equal(
            'vimalaya command failed:\n```sh\n'
                .. table.concat(command, ' ') .. '\n```'
                .. '\n```stdout\nHimalaya stdout\n```\n```stderr\nHimalaya stderr\n```',
            message
        )
    end)

    it("send attaches the file from the attach field", function()
        local command
        open_first_message()
        vim.cmd('Mail reply')
        vim.api.nvim_buf_set_lines(0, -2, -2, false, { 'attach: /bin/bash' })
        executable_mocks['himalaya message compose'] = function(args)
            command = args
            return { code = 0, stdout = 'Message successfully sent\n', stderr = '' }
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
        executable_mocks['himalaya message compose'] = function(args)
            command = args
            return { code = 0, stdout = 'Message successfully sent\n', stderr = '' }
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

    it("send strips display names from recipients before passing them to himalaya", function()
        local command
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
        executable_mocks['himalaya message compose'] = function(args)
            command = args
            return { code = 0, stdout = 'Message successfully sent\n', stderr = '' }
        end

        vim.cmd('Mail send')

        assert.is_true(vim.wait(1000, function()
            return command ~= nil
        end))
        assert.same({
            'himalaya', 'message', 'compose',
            '--from', 'example@gmail.com',
            '--to', 'sender@example.test',
            '--cc', 'copy@example.test',
            '--bcc', 'blind-copy@example.test',
            '--subject', 'Re: First example message',
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

    it("attaches a ranged directory as a tar.gz archive", function()
        vim.cmd('Mail new')
        local email = vim.api.nvim_get_current_buf()
        local directory = download_dir .. '/payload'
        vim.fn.mkdir(directory, 'p')
        local source = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_buf_set_lines(source, 0, -1, false, { directory })
        vim.api.nvim_set_current_buf(source)
        executable_mocks['tar -czf ' .. directory .. '.tar.gz -C ' .. download_dir .. ' payload'] = function()
            return { code = 0, stdout = '', stderr = '' }
        end

        vim.cmd('1,1Mail')

        assert.is_true(vim.tbl_contains(
            vim.api.nvim_buf_get_lines(email, 0, -1, false),
            'attach: ' .. directory .. '.tar.gz'
        ))
    end)

    it("reports that a ranged directory is compressing with an info diagnostic", function()
        vim.cmd('Mail new')
        local email = vim.api.nvim_get_current_buf()
        local directory = download_dir .. '/payload'
        vim.fn.mkdir(directory, 'p')
        local source = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_buf_set_lines(source, 0, -1, false, { directory })
        vim.api.nvim_set_current_buf(source)
        executable_mocks['tar -czf ' .. directory .. '.tar.gz -C ' .. download_dir .. ' payload'] = function()
            return { code = 0, stdout = '', stderr = '' }
        end

        vim.cmd('1,1Mail')

        local infos = vim.diagnostic.get(email, { severity = vim.diagnostic.severity.INFO })
        assert.equal(1, #infos)
        assert.equal('compressing directory into archive: ' .. directory .. '.tar.gz', infos[1].message)
    end)

    it("attaches interweaved files and directories in a ranged selection", function()
        vim.cmd('Mail new')
        local email = vim.api.nvim_get_current_buf()
        local directory = download_dir .. '/payload'
        vim.fn.mkdir(directory, 'p')
        local source = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_buf_set_lines(source, 0, -1, false, { '/bin/bash', directory, '/bin/sh' })
        vim.api.nvim_set_current_buf(source)
        executable_mocks['tar -czf ' .. directory .. '.tar.gz -C ' .. download_dir .. ' payload'] = function()
            return { code = 0, stdout = '', stderr = '' }
        end

        vim.cmd('1,3Mail')

        local attachments = vim.tbl_filter(function(line)
            return vim.startswith(line, 'attach:')
        end, vim.api.nvim_buf_get_lines(email, 0, -1, false))
        assert.same({
            'attach: /bin/bash',
            'attach: ' .. directory .. '.tar.gz',
            'attach: /bin/sh',
        }, attachments)
    end)

    it("reports the full command when compressing a directory fails", function()
        local message
        local level
        vim.cmd('Mail new')
        local directory = download_dir .. '/payload'
        vim.fn.mkdir(directory, 'p')
        local source = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_buf_set_lines(source, 0, -1, false, { directory })
        vim.api.nvim_set_current_buf(source)
        local command = 'tar -czf ' .. directory .. '.tar.gz -C ' .. download_dir .. ' payload'
        executable_mocks[command] = function()
            return { code = 127, stdout = '', stderr = 'tar: command not found\n' }
        end
        vim.notify = function(notification, notification_level)
            message = notification
            level = notification_level
        end

        vim.cmd('1,1Mail')

        assert.is_true(vim.wait(1000, function()
            return message ~= nil
        end))
        assert.equal(
            'vimalaya command failed:\n```sh\n'
                .. command .. '\n```'
                .. '\n```stdout\n\n```\n```stderr\ntar: command not found\n```',
            message
        )
        assert.equal(vim.log.levels.ERROR, level)
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
        executable_mocks['himalaya message compose'] = function()
            return { code = 0, stdout = 'Message successfully sent\n', stderr = '' }
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

    it("warns with a diagnostic when an attached file does not exist", function()
        vim.cmd('Mail new')
        local email = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_set_lines(email, -1, -1, false, {
            'attach: /bin/sh',
            'attach: /does/not/exist.txt',
        })

        vim.api.nvim_exec_autocmds('TextChanged', { buffer = email })

        local diagnostics = vim.diagnostic.get(email)
        assert.equal(1, #diagnostics)
        assert.equal(vim.diagnostic.severity.WARN, diagnostics[1].severity)
        assert.equal('attached file does not exist: /does/not/exist.txt', diagnostics[1].message)
        assert.equal('attach: /does/not/exist.txt', vim.api.nvim_buf_get_lines(
            email, diagnostics[1].lnum, diagnostics[1].lnum + 1, false)[1])
    end)

    it("underlines the filename when an attached file does not exist", function()
        vim.cmd('Mail new')
        local email = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_set_lines(email, -1, -1, false, {
            'attach: /does/not/exist.txt',
        })

        vim.api.nvim_exec_autocmds('TextChanged', { buffer = email })

        local diagnostics = vim.diagnostic.get(email)
        assert.equal(1, #diagnostics)
        assert.equal(8, diagnostics[1].col)
        assert.equal(27, diagnostics[1].end_col)
    end)

    it("defines :VimalayaKeywordprg in vimalaya buffers", function()
        open_first_message()

        assert.is_true(vim.tbl_contains(vim.fn.getcompletion('VimalayaKeywordprg', 'command'), 'VimalayaKeywordprg'))
    end)

    it("does not define :VimalayaKeywordprg outside vimalaya buffers", function()
        vim.cmd('enew')

        assert.is_false(vim.tbl_contains(vim.fn.getcompletion('VimalayaKeywordprg', 'command'), 'VimalayaKeywordprg'))
    end)

    it("sets keywordprg to :VimalayaKeywordprg in vimalaya buffers", function()
        open_first_message()

        assert.equal(':VimalayaKeywordprg', vim.bo.keywordprg)
    end)

    it("hovers documentation for From when pressing K", function()
        local open_floating_preview = spy.on(vim.lsp.util, 'open_floating_preview')
        open_first_message()
        vim.api.nvim_win_set_cursor(0, { 1, 0 })

        vim.api.nvim_feedkeys(vim.keycode('K'), 'x', false)

        assert.spy(open_floating_preview).was_called()
        assert.same({ header_docs.from }, open_floating_preview.calls[1].vals[1])
        open_floating_preview:revert()
    end)

    it("hovers documentation for To when pressing K", function()
        local open_floating_preview = spy.on(vim.lsp.util, 'open_floating_preview')
        open_first_message()
        vim.api.nvim_win_set_cursor(0, { 2, 0 })

        vim.api.nvim_feedkeys(vim.keycode('K'), 'x', false)

        assert.spy(open_floating_preview).was_called()
        assert.same({ header_docs.to }, open_floating_preview.calls[1].vals[1])
        open_floating_preview:revert()
    end)

    it("hovers documentation for Cc when pressing K", function()
        local open_floating_preview = spy.on(vim.lsp.util, 'open_floating_preview')
        open_first_message()
        vim.api.nvim_win_set_cursor(0, { 3, 0 })

        vim.api.nvim_feedkeys(vim.keycode('K'), 'x', false)

        assert.spy(open_floating_preview).was_called()
        assert.same({ header_docs.cc }, open_floating_preview.calls[1].vals[1])
        open_floating_preview:revert()
    end)

    it("hovers documentation for Bcc when pressing K", function()
        local open_floating_preview = spy.on(vim.lsp.util, 'open_floating_preview')
        open_first_message()
        vim.api.nvim_buf_set_lines(0, 3, 3, false, { 'Bcc: Example Blind <blind@example.test>' })
        vim.api.nvim_win_set_cursor(0, { 4, 0 })

        vim.api.nvim_feedkeys(vim.keycode('K'), 'x', false)

        assert.spy(open_floating_preview).was_called()
        assert.same({ header_docs.bcc }, open_floating_preview.calls[1].vals[1])
        open_floating_preview:revert()
    end)

    it("hovers documentation for Subject when pressing K", function()
        local open_floating_preview = spy.on(vim.lsp.util, 'open_floating_preview')
        open_first_message()
        vim.api.nvim_win_set_cursor(0, { 4, 0 })

        vim.api.nvim_feedkeys(vim.keycode('K'), 'x', false)

        assert.spy(open_floating_preview).was_called()
        assert.same({ header_docs.subject }, open_floating_preview.calls[1].vals[1])
        open_floating_preview:revert()
    end)

    it("hovers documentation for Message-ID when pressing K", function()
        local open_floating_preview = spy.on(vim.lsp.util, 'open_floating_preview')
        open_first_message()
        vim.api.nvim_win_set_cursor(0, { 6, 0 })

        vim.api.nvim_feedkeys(vim.keycode('K'), 'x', false)

        assert.spy(open_floating_preview).was_called()
        assert.same({ header_docs.message_id }, open_floating_preview.calls[1].vals[1])
        open_floating_preview:revert()
    end)

    it("hovers documentation for In-Reply-To when pressing K", function()
        local open_floating_preview = spy.on(vim.lsp.util, 'open_floating_preview')
        open_first_message()
        vim.api.nvim_buf_set_lines(0, 6, 6, false, { 'In-Reply-To: <example-0@example.test>' })
        vim.api.nvim_win_set_cursor(0, { 7, 0 })

        vim.api.nvim_feedkeys(vim.keycode('K'), 'x', false)

        assert.spy(open_floating_preview).was_called()
        assert.same({ header_docs.in_reply_to }, open_floating_preview.calls[1].vals[1])
        open_floating_preview:revert()
    end)

    it("hovers documentation for References when pressing K", function()
        local open_floating_preview = spy.on(vim.lsp.util, 'open_floating_preview')
        open_first_message()
        vim.api.nvim_buf_set_lines(0, 6, 6, false, { 'References: <example-0@example.test>' })
        vim.api.nvim_win_set_cursor(0, { 7, 0 })

        vim.api.nvim_feedkeys(vim.keycode('K'), 'x', false)

        assert.spy(open_floating_preview).was_called()
        assert.same({ header_docs.references }, open_floating_preview.calls[1].vals[1])
        open_floating_preview:revert()
    end)

    it("hovers documentation for Comments when pressing K", function()
        local open_floating_preview = spy.on(vim.lsp.util, 'open_floating_preview')
        open_first_message()
        vim.api.nvim_buf_set_lines(0, 6, 6, false, { 'Comments: An example comment' })
        vim.api.nvim_win_set_cursor(0, { 7, 0 })

        vim.api.nvim_feedkeys(vim.keycode('K'), 'x', false)

        assert.spy(open_floating_preview).was_called()
        assert.same({ header_docs.comments }, open_floating_preview.calls[1].vals[1])
        open_floating_preview:revert()
    end)

    it("hovers documentation for Keywords when pressing K", function()
        local open_floating_preview = spy.on(vim.lsp.util, 'open_floating_preview')
        open_first_message()
        vim.api.nvim_buf_set_lines(0, 6, 6, false, { 'Keywords: example, message' })
        vim.api.nvim_win_set_cursor(0, { 7, 0 })

        vim.api.nvim_feedkeys(vim.keycode('K'), 'x', false)

        assert.spy(open_floating_preview).was_called()
        assert.same({ header_docs.keywords }, open_floating_preview.calls[1].vals[1])
        open_floating_preview:revert()
    end)
end)
