local M = {}

local main_menu_name = "vimalaya main menu"

function M.open_new_message()
    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(bufnr, vim.fn.tempname() .. ' vimalaya new email')
    vim.api.nvim_buf_set_var(bufnr, "vimalaya", true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'to: ', 'cc: ', 'bcc: ', 'subject: ' })
    vim.api.nvim_set_current_buf(bufnr)
end

function M.open_message(mailbox, id, subject)
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        local has_mailbox, message_mailbox = pcall(vim.api.nvim_buf_get_var, bufnr, "vimalaya_message_mailbox")
        local has_id, message_id = pcall(vim.api.nvim_buf_get_var, bufnr, "vimalaya_message_id")
        if has_mailbox and has_id and message_mailbox == mailbox and message_id == tostring(id) then
            vim.api.nvim_set_current_buf(bufnr)
            return
        end
    end

    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(bufnr, vim.fn.tempname() .. ' vimalaya ' .. subject)
    vim.api.nvim_buf_set_var(bufnr, "vimalaya", true)
    vim.api.nvim_buf_set_var(bufnr, "vimalaya_message_mailbox", mailbox)
    vim.api.nvim_buf_set_var(bufnr, "vimalaya_message_id", tostring(id))
    vim.api.nvim_set_current_buf(bufnr)

    vim.system({ 'himalaya', 'message', 'read', '--mailbox', mailbox, id }, {}, function(result)
        vim.schedule(function()
            if result.code ~= 0 or not vim.api.nvim_buf_is_valid(bufnr) then
                return
            end

            local lines = vim.split(result.stdout, '\n', { plain = true })
            if lines[#lines] == '' then
                table.remove(lines)
            end

            if vim.api.nvim_buf_is_valid(bufnr) then
                vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
            end
        end)
    end)
end

function M.open_mailbox(mailbox)
    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(bufnr, vim.fn.tempname() .. ' vimalaya ' .. mailbox .. ' mailbox')
    vim.api.nvim_buf_set_var(bufnr, "vimalaya", true)
    vim.bo[bufnr].readonly = true
    vim.api.nvim_set_current_buf(bufnr)

    vim.system({ 'himalaya', 'envelope', 'list', '--mailbox', mailbox, '--json', '--page-size', '100' }, {}, function(result)
        vim.schedule(function()
            if result.code ~= 0 or not vim.api.nvim_buf_is_valid(bufnr) then
                return
            end

            local envelopes = vim.json.decode(result.stdout)
            local lines = {}
            local envelope_ids = {}
            local envelope_subjects = {}
            for _, envelope in ipairs(envelopes.envelopes) do
                table.insert(lines, envelope.date .. ' ' .. envelope.subject)
                table.insert(envelope_ids, envelope.id)
                table.insert(envelope_subjects, envelope.subject)
            end

            vim.bo[bufnr].readonly = false
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
            vim.bo[bufnr].readonly = true
            vim.keymap.set('n', '<CR>', function()
                local line = vim.fn.line('.')
                M.open_message(mailbox, envelope_ids[line], envelope_subjects[line])
            end, { buffer = bufnr })
        end)
    end)
end

function M.open_main_menu()
    if vim.fn.executable('himalaya') == 0 then
        vim.notify('himalaya is not installed', vim.log.levels.ERROR)
        return
    end

    local is_main_menu = pcall(vim.api.nvim_buf_get_var, 0, "vimalaya_main_menu")
    if is_main_menu then
        return
    end

    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        is_main_menu = pcall(vim.api.nvim_buf_get_var, bufnr, "vimalaya_main_menu")
        if is_main_menu then
            vim.api.nvim_set_current_buf(bufnr)
            return
        end
    end

    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(bufnr, vim.fn.tempname() .. ' ' .. main_menu_name)
    vim.api.nvim_buf_set_var(bufnr, "vimalaya", true)
    vim.api.nvim_buf_set_var(bufnr, "vimalaya_main_menu", true)
    vim.bo[bufnr].readonly = true
    vim.keymap.set('n', '<CR>', function()
        M.open_mailbox(vim.api.nvim_get_current_line())
    end, { buffer = bufnr })
    vim.api.nvim_set_current_buf(bufnr)

    vim.system({ 'himalaya', 'mailbox', 'list', '--json' }, {}, function(result)
        vim.schedule(function()
            if result.code ~= 0 or not vim.api.nvim_buf_is_valid(bufnr) then
                return
            end

            local mailboxes = vim.json.decode(result.stdout)
            local lines = {}
            for _, mailbox in ipairs(mailboxes.mailboxes) do
                table.insert(lines, mailbox.name)
            end

            vim.bo[bufnr].readonly = false
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
            vim.bo[bufnr].readonly = true
        end)
    end)
end

function M.close()
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if pcall(vim.api.nvim_buf_get_var, bufnr, "vimalaya") then
            vim.api.nvim_buf_delete(bufnr, { force = true })
        end
    end
end

function M.append_response(kind)
    if not pcall(vim.api.nvim_buf_get_var, 0, "vimalaya_message_id") then
        vim.notify(':Mail ' .. kind .. ' is only available in email buffers', vim.log.levels.ERROR)
        return
    end

    local headers = {}
    for _, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
        if line == '' then
            break
        end

        local name, value = line:match('^([^:]+):%s*(.*)$')
        if name then
            headers[name:lower()] = value
        end
    end

    local response = {
        reply = { title = 'Reply', subject = 'Re: ' },
        replyall = { title = 'Reply All', subject = 'Re: ' },
        forward = { title = 'Forward', subject = 'Fwd: ' },
    }
    local action = response[kind]
    vim.api.nvim_buf_set_lines(0, -1, -1, false, {
        '',
        '',
        '--- ' .. action.title .. ' ---',
        'to: ' .. (headers.from or ''),
        'cc: ' .. (headers.cc or ''),
        'bcc: ',
        'subject: ' .. action.subject .. (headers.subject or ''),
        '',
    })
end

return M
