local M = {}

local main_menu_name = "vimalaya main menu"
local last_compose_bufnr

local function record_account_settings_from_config_line(accounts, account, line)
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

local function find_default_account_email()
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
            record_account_settings_from_config_line(accounts, account, line)
        end
    end

    for _, details in pairs(accounts) do
        if details.default then
            return details.email
        end
    end
end

function M.open_new_message_buffer()
    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(bufnr, vim.fn.tempname() .. ' vimalaya new email')
    vim.api.nvim_buf_set_var(bufnr, "vimalaya", true)
    vim.api.nvim_buf_set_var(bufnr, "vimalaya_new_message", true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'to: ', 'cc: ', 'bcc: ', 'subject: ' })
    last_compose_bufnr = bufnr
    vim.api.nvim_set_current_buf(bufnr)
end

local function find_attachment_filename_line(bufnr, attachment_index)
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
        end
        if found == attachment_index then
            return index
        end
    end
end

local function resolve_download_directory()
    if vim.env.XDG_DOWNLOAD_DIR then
        return vim.fn.expand(vim.env.XDG_DOWNLOAD_DIR)
    end

    local config_home = vim.env.XDG_CONFIG_HOME or (vim.env.HOME .. '/.config')
    local ok, lines = pcall(vim.fn.readfile, config_home .. '/user-dirs.dirs')
    if not ok then
        return vim.env.HOME .. '/Downloads'
    end
    for _, line in ipairs(lines) do
        local directory = line:match('^XDG_DOWNLOAD_DIR="(.*)"$')
        if directory then
            return directory:gsub('%$HOME', vim.env.HOME)
        end
    end

    return vim.env.HOME .. '/Downloads'
end

local function move_attachment_to_downloads_and_display_path(
    bufnr,
    attachment_index,
    attachment,
    downloaded,
    temporary_dir
)
    local destination_dir = resolve_download_directory()
    vim.fn.mkdir(destination_dir, 'p')
    local destination = destination_dir .. '/' .. vim.fn.fnamemodify(downloaded.path, ':t')
    if vim.fn.rename(downloaded.path, destination) ~= 0 then
        vim.fn.delete(temporary_dir, 'rf')
        vim.notify('Could not move attachment to ' .. destination, vim.log.levels.ERROR)
        return
    end
    vim.fn.delete(temporary_dir, 'rf')

    if not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end
    local line = find_attachment_filename_line(bufnr, attachment_index)
    if not line then
        return
    end
    vim.api.nvim_buf_set_lines(bufnr, line - 1, line, false, {
        '  filename: ' .. (attachment.filename or '') .. ' ' .. destination,
    })
end

local function process_attachment_scan_result(
    bufnr,
    attachment_index,
    attachment,
    downloaded,
    temporary_dir,
    scan_result
)
    if scan_result.code == 0 then
        move_attachment_to_downloads_and_display_path(bufnr, attachment_index, attachment, downloaded, temporary_dir)
        return
    end

    vim.fn.delete(temporary_dir, 'rf')
    if scan_result.code == 1 then
        vim.notify('ClamAV detected a virus; attachment was deleted', vim.log.levels.ERROR)
        return
    end
    vim.notify('ClamAV could not scan the attachment; attachment was deleted', vim.log.levels.ERROR)
end

local function scan_downloaded_attachment(bufnr, attachment_index, attachment, downloaded, temporary_dir)
    vim.system({ 'clamscan', downloaded.path }, {}, function(scan_result)
        vim.schedule(function()
            process_attachment_scan_result(
                bufnr,
                attachment_index,
                attachment,
                downloaded,
                temporary_dir,
                scan_result
            )
        end)
    end)
end

local function process_attachment_download_result(
    bufnr,
    attachment_index,
    attachment,
    temporary_dir,
    command,
    download_result
)
    if download_result.code ~= 0 then
        vim.fn.delete(temporary_dir, 'rf')
        vim.notify(
            table.concat(command, ' ') .. '\n' .. download_result.stdout .. download_result.stderr,
            vim.log.levels.ERROR
        )
        return
    end
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end

    local downloaded = vim.json.decode(download_result.stdout).attachments[1]
    if not downloaded or not downloaded.path then
        vim.fn.delete(temporary_dir, 'rf')
        return
    end
    scan_downloaded_attachment(bufnr, attachment_index, attachment, downloaded, temporary_dir)
end

local function download_and_scan_attachment(bufnr, mailbox, id, attachment_index, attachment)
    local temporary_dir = vim.fn.tempname()
    vim.fn.mkdir(temporary_dir, 'p')
    local command = {
        'himalaya', 'attachment', 'download', '--mailbox', mailbox, '--json', id, attachment.id,
        '--dir', temporary_dir,
    }
    vim.system(command, {}, function(download_result)
        vim.schedule(function()
            process_attachment_download_result(
                bufnr,
                attachment_index,
                attachment,
                temporary_dir,
                command,
                download_result
            )
        end)
    end)
end

local function find_attachment_index_at_cursor(bufnr, attachments)
    local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
    for index = 1, #attachments do
        if find_attachment_filename_line(bufnr, index) == cursor_line then
            return index
        end
    end
end

local function download_attachment_at_cursor(bufnr, mailbox, id, attachments)
    local attachment_index = find_attachment_index_at_cursor(bufnr, attachments)
    if not attachment_index then
        return
    end
    if vim.fn.executable('clamscan') == 0 then
        vim.notify('ClamAV antivirus is not installed; attachments cannot be downloaded', vim.log.levels.ERROR)
        return
    end
    download_and_scan_attachment(bufnr, mailbox, id, attachment_index, attachments[attachment_index])
end

local function display_attachments_and_enable_downloads(bufnr, mailbox, id, result)
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
        download_attachment_at_cursor(bufnr, mailbox, id, attachments)
    end, { buffer = bufnr })
end

local function request_attachment_list(bufnr, mailbox, id)
    vim.system({ 'himalaya', 'attachment', 'list', '--mailbox', mailbox, '--json', id }, {}, function(result)
        vim.schedule(function()
            display_attachments_and_enable_downloads(bufnr, mailbox, id, result)
        end)
    end)
end

local function display_message_and_request_attachments(bufnr, mailbox, id, result)
    if result.code ~= 0 or not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end

    local lines = vim.split(result.stdout, '\n', { plain = true })
    if lines[#lines] == '' then
        table.remove(lines)
    end

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    request_attachment_list(bufnr, mailbox, tostring(id))
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
            display_message_and_request_attachments(bufnr, mailbox, id, result)
        end)
    end)
end

local function open_message_at_cursor(mailbox, envelope_ids, envelope_subjects)
    local line = vim.fn.line('.')
    M.open_message(mailbox, envelope_ids[line], envelope_subjects[line])
end

local function display_envelopes_and_enable_opening(bufnr, mailbox, result)
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
        open_message_at_cursor(mailbox, envelope_ids, envelope_subjects)
    end, { buffer = bufnr })
end

local function request_envelope_list(bufnr, mailbox)
    vim.system({ 'himalaya', 'envelope', 'list', '--mailbox', mailbox, '--json', '--page-size', '100' }, {}, function(result)
        vim.schedule(function()
            display_envelopes_and_enable_opening(bufnr, mailbox, result)
        end)
    end)
end

function M.open_mailbox_buffer(mailbox)
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
    request_envelope_list(bufnr, mailbox)
end

local function display_mailbox_list(bufnr, result)
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
end

local function request_mailbox_list(bufnr)
    vim.system({ 'himalaya', 'mailbox', 'list', '--json' }, {}, function(result)
        vim.schedule(function()
            display_mailbox_list(bufnr, result)
        end)
    end)
end

function M.open_main_menu_buffer()
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
        M.open_mailbox_buffer(vim.api.nvim_get_current_line())
    end, { buffer = bufnr })
    vim.api.nvim_set_current_buf(bufnr)

    request_mailbox_list(bufnr)
end

function M.refresh_current_mail_view()
    if pcall(vim.api.nvim_buf_get_var, 0, "vimalaya_main_menu") then
        request_mailbox_list(vim.api.nvim_get_current_buf())
        return
    end

    local has_mailbox, mailbox = pcall(vim.api.nvim_buf_get_var, 0, "vimalaya_mailbox")
    if has_mailbox then
        request_envelope_list(vim.api.nvim_get_current_buf(), mailbox)
    end
end

function M.close_all_mail_buffers()
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if pcall(vim.api.nvim_buf_get_var, bufnr, "vimalaya") then
            vim.api.nvim_buf_delete(bufnr, { force = true })
        end
    end
end

function M.append_response_form(kind)
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

function M.attach_paths_to_message(paths, new_message)
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
        M.open_new_message_buffer()
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

local function process_message_send_result(result, command, bufnr, is_new_message, response_start)
    if result.code ~= 0 then
        vim.notify(table.concat(command, ' ') .. '\n' .. result.stdout .. result.stderr, vim.log.levels.ERROR)
        return
    end

    if vim.trim(result.stdout) == 'Message successfully sent' and vim.api.nvim_buf_is_valid(bufnr) then
        if is_new_message then
            vim.api.nvim_buf_delete(bufnr, { force = true })
        else
            vim.api.nvim_buf_set_lines(bufnr, response_start - 3, -1, false, {})
        end
    end
    vim.notify(vim.trim(result.stdout))
end

local function record_compose_header(headers, name, value)
    if not name then
        return
    end

    name = name:lower()
    if type(headers[name]) ~= 'table' then
        headers[name] = value
        return
    end
    if value ~= '' then
        table.insert(headers[name], value)
    end
end

function M.send_composed_message()
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
        record_compose_header(headers, name, value)
    end

    local command = { 'himalaya', 'message', 'compose' }
    local email = find_default_account_email()
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
            process_message_send_result(result, command, bufnr, is_new_message, response_start)
        end)
    end)
end

return M
