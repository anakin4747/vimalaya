local M = {}

local main_menu_name = "vimalaya main menu"
local last_compose_bufnr

local function configured_email()
    local config_dir = vim.env.XDG_CONFIG_HOME or (vim.env.HOME .. '/.config')
    local ok, lines = pcall(vim.fn.readfile, config_dir .. '/himalaya/config.toml')
    if not ok then
        return
    end

    local accounts = {}
    local account
    for _, line in ipairs(lines) do
        account = line:match('^%[accounts%.([^%]]+)%]$') or account
        if account then
            accounts[account] = accounts[account] or {}
            local key, value = line:match('^([%w%.]+)%s*=%s*(.-)%s*$')
            if value then
                value = value:match('^"(.*)"$') or value
            end
            if key == 'default' then
                accounts[account].default = value == 'true'
            elseif key == 'smtp.sasl.plain.username' then
                accounts[account].email = value
            end
        end
    end

    for _, details in pairs(accounts) do
        if details.default then
            return details.email
        end
    end
end

function M.open_new_message()
    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(bufnr, vim.fn.tempname() .. ' vimalaya new email')
    vim.api.nvim_buf_set_var(bufnr, "vimalaya", true)
    vim.api.nvim_buf_set_var(bufnr, "vimalaya_new_message", true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'to: ', 'cc: ', 'bcc: ', 'subject: ' })
    last_compose_bufnr = bufnr
    vim.api.nvim_set_current_buf(bufnr)
end

local function attachment_line(bufnr, attachment_index)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local attachments_start
    for index = #lines, 1, -1 do
        if lines[index] == 'attachments:' then
            attachments_start = index
            break
        end
    end
    if not attachments_start then
        return
    end

    local found = 0
    for index = attachments_start + 1, #lines do
        if vim.startswith(lines[index], '  filename: ') then
            found = found + 1
            if found == attachment_index then
                return index
            end
        end
    end
end

local function load_attachments(bufnr, mailbox, id)
    vim.system({ 'himalaya', 'attachment', 'list', '--mailbox', mailbox, '--json', id }, {}, function(result)
        vim.schedule(function()
            if result.code ~= 0 or not vim.api.nvim_buf_is_valid(bufnr) then
                return
            end

            local attachments = vim.json.decode(result.stdout).attachments
            if #attachments == 0 then
                return
            end

            local lines = { '', 'attachments:' }
            for _, attachment in ipairs(attachments) do
                vim.list_extend(lines, {
                    '  filename: ' .. (attachment.filename or ''),
                    '    mime: ' .. (attachment.mime or ''),
                    '    size: ' .. attachment.size,
                })
            end
            local line_count = vim.api.nvim_buf_line_count(bufnr)
            vim.api.nvim_buf_set_lines(bufnr, line_count, line_count, false, lines)

            vim.keymap.set('n', '<CR>', function()
                local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
                local attachment_index
                for index = 1, #attachments do
                    if attachment_line(bufnr, index) == cursor_line then
                        attachment_index = index
                        break
                    end
                end
                if not attachment_index then
                    return
                end

                local attachment = attachments[attachment_index]
                vim.system({
                    'himalaya', 'attachment', 'download', '--mailbox', mailbox, '--json', id, attachment.id,
                }, {}, function(download_result)
                    vim.schedule(function()
                        if download_result.code ~= 0 or not vim.api.nvim_buf_is_valid(bufnr) then
                            return
                        end

                        local downloaded = vim.json.decode(download_result.stdout).attachments[1]
                        local line = attachment_line(bufnr, attachment_index)
                        if downloaded and downloaded.path and line then
                            vim.api.nvim_buf_set_lines(bufnr, line - 1, line, false, {
                                '  filename: ' .. (attachment.filename or '') .. ' ' .. downloaded.path,
                            })
                        end
                    end)
                end)
            end, { buffer = bufnr })
        end)
    end)
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
                load_attachments(bufnr, mailbox, tostring(id))
            end
        end)
    end)
end

local function load_mailbox(bufnr, mailbox)
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

function M.open_mailbox(mailbox)
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        local has_mailbox, existing_mailbox = pcall(vim.api.nvim_buf_get_var, bufnr, "vimalaya_mailbox")
        if has_mailbox and existing_mailbox == mailbox then
            vim.api.nvim_set_current_buf(bufnr)
            return
        end
    end

    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(bufnr, vim.fn.tempname() .. ' vimalaya ' .. mailbox .. ' mailbox')
    vim.api.nvim_buf_set_var(bufnr, "vimalaya", true)
    vim.api.nvim_buf_set_var(bufnr, "vimalaya_mailbox", mailbox)
    vim.bo[bufnr].readonly = true
    vim.api.nvim_set_current_buf(bufnr)
    load_mailbox(bufnr, mailbox)
end

local function load_main_menu(bufnr)
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

    load_main_menu(bufnr)
end

function M.refresh()
    if pcall(vim.api.nvim_buf_get_var, 0, "vimalaya_main_menu") then
        load_main_menu(vim.api.nvim_get_current_buf())
        return
    end

    local has_mailbox, mailbox = pcall(vim.api.nvim_buf_get_var, 0, "vimalaya_mailbox")
    if has_mailbox then
        load_mailbox(vim.api.nvim_get_current_buf(), mailbox)
    end
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
    last_compose_bufnr = vim.api.nvim_get_current_buf()
end

function M.attach_paths(paths, new_message)
    paths = vim.tbl_map(function(path)
        return vim.fn.fnamemodify(path, ':p')
    end, paths)

    for _, path in ipairs(paths) do
        if vim.fn.filereadable(path) ~= 1 then
            vim.notify(':Mail cannot attach ' .. path .. ': not a file', vim.log.levels.ERROR)
            return
        end
    end

    if new_message or not last_compose_bufnr or not vim.api.nvim_buf_is_valid(last_compose_bufnr) then
        M.open_new_message()
    end

    local lines = vim.api.nvim_buf_get_lines(last_compose_bufnr, 0, -1, false)
    local attachments = vim.tbl_map(function(path)
        return 'attach: ' .. path
    end, paths)
    for index = #lines, 1, -1 do
        if lines[index] == 'attach: ' then
            vim.api.nvim_buf_set_lines(last_compose_bufnr, index - 1, index, false, attachments)
            return
        elseif vim.startswith(lines[index], 'attach: ') then
            vim.api.nvim_buf_set_lines(last_compose_bufnr, index, index, false, attachments)
            return
        end
    end

    local compose_start = 1
    local response_markers = {
        ['--- Reply ---'] = true,
        ['--- Reply All ---'] = true,
        ['--- Forward ---'] = true,
    }
    for index, line in ipairs(lines) do
        if response_markers[line] then
            compose_start = index + 1
        end
    end

    local insert_at = #lines
    for index = compose_start, #lines do
        if lines[index] == '' then
            insert_at = index - 1
            break
        end
    end
    vim.api.nvim_buf_set_lines(last_compose_bufnr, insert_at, insert_at, false, attachments)
end

function M.send_response()
    local bufnr = vim.api.nvim_get_current_buf()
    local is_message = pcall(vim.api.nvim_buf_get_var, 0, "vimalaya_message_id")
    local is_new_message = pcall(vim.api.nvim_buf_get_var, 0, "vimalaya_new_message")
    if not is_message and not is_new_message then
        vim.notify(':Mail send is only available in email buffers', vim.log.levels.ERROR)
        return
    end

    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local response_start = is_new_message and 0 or nil
    local response_markers = {
        ['--- Reply ---'] = true,
        ['--- Reply All ---'] = true,
        ['--- Forward ---'] = true,
    }
    for index, line in ipairs(lines) do
        if response_markers[line] then
            response_start = index
        end
    end
    if not response_start then
        return
    end

    local headers = { to = {}, cc = {}, bcc = {}, attach = {} }
    local body_start
    for index = response_start + 1, #lines do
        if lines[index] == '' then
            body_start = index + 1
            break
        end

        local name, value = lines[index]:match('^([^:]+):%s*(.*)$')
        if name then
            name = name:lower()
            if headers[name] and type(headers[name]) == 'table' then
                if value ~= '' then
                    table.insert(headers[name], value)
                end
            else
                headers[name] = value
            end
        end
    end

    local command = { 'himalaya', 'message', 'compose' }
    local email = configured_email()
    if email then
        vim.list_extend(command, { '--from', email })
    end
    for _, name in ipairs({ 'to', 'cc', 'bcc' }) do
        for _, value in ipairs(headers[name]) do
            vim.list_extend(command, { '--' .. name, value })
        end
    end
    if headers.subject and headers.subject ~= '' then
        vim.list_extend(command, { '--subject', headers.subject })
    end
    for _, value in ipairs(headers.attach) do
        vim.list_extend(command, { '--attach', value })
    end
    vim.list_extend(command, {
        '--body', table.concat(vim.list_slice(lines, body_start or (#lines + 1)), '\n'), '--send',
    })

    vim.system(command, {}, function(result)
        vim.schedule(function()
            if result.code == 0 then
                if vim.trim(result.stdout) == 'Message successfully sent' and vim.api.nvim_buf_is_valid(bufnr) then
                    if is_new_message then
                        vim.api.nvim_buf_delete(bufnr, { force = true })
                    else
                        vim.api.nvim_buf_set_lines(bufnr, response_start - 3, -1, false, {})
                    end
                end
                vim.notify(vim.trim(result.stdout))
            else
                vim.notify(table.concat(command, ' ') .. '\n' .. result.stdout .. result.stderr, vim.log.levels.ERROR)
            end
        end)
    end)
end

return M
