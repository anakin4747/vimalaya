local M = {}

local main_menu_name = "vimalaya main menu"
local attachment_diagnostics_namespace = vim.api.nvim_create_namespace('vimalaya_attachments')
vim.diagnostic.config({
    underline = true,
    virtual_text = false,
    signs = false,
    update_in_insert = true,
}, attachment_diagnostics_namespace)
local compressing_archives = {}
local last_compose_bufnr
local enable_attachment_diagnostics
local response_actions = {
    reply = { title = 'Reply', subject = 'Re: ' },
    replyall = { title = 'Reply All', subject = 'Re: ' },
    forward = { title = 'Forward', subject = 'Fwd: ' },
}
local response_markers = {}
for _, action in pairs(response_actions) do
    response_markers['--- ' .. action.title .. ' ---'] = true
end

local function notify_command_failure(command, result)
    if type(command) == 'table' then
        command = table.concat(command, ' ')
    end
    vim.notify(
        'vimalaya command failed:\n```sh\n'
            .. command
            .. '\n```stdout\n'
            .. vim.trim(result.stdout or '')
            .. '\n```\n```stderr\n'
            .. vim.trim(result.stderr or '')
            .. '\n```',
        vim.log.levels.ERROR
    )
end

local function find_last_response_start(lines)
    local response_start
    for index, line in ipairs(lines) do
        if response_markers[line] then
            response_start = index
        end
    end
    return response_start
end

local function replace_readonly_buffer_lines(bufnr, lines)
    vim.bo[bufnr].readonly = false
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.bo[bufnr].readonly = true
end

local function parse_config_value(line)
    local value = line:match('=%s*(.-)%s*$')
    return value and (value:match('^"(.*)"$') or value)
end

local function find_default_account_email()
    local config_dir = vim.env.XDG_CONFIG_HOME or (vim.env.HOME .. '/.config')
    local ok, lines = pcall(vim.fn.readfile, config_dir .. '/himalaya/config.toml')
    if not ok then
        return
    end

    local email
    local is_default = false
    for _, line in ipairs(lines) do
        if line:match('^%[accounts%.') and is_default then
            return email
        elseif line:match('^%[accounts%.') then
            email = nil
            is_default = false
        elseif line:match('^default%s*=') then
            is_default = parse_config_value(line) == 'true'
        elseif line:match('^smtp%.sasl%.plain%.username%s*=') then
            email = parse_config_value(line)
        end
    end

    if is_default then
        return email
    end
end

function M.open_new_message_buffer()
    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(bufnr, vim.fn.tempname() .. ' vimalaya new email')
    vim.api.nvim_buf_set_var(bufnr, "vimalaya", true)
    vim.api.nvim_buf_set_var(bufnr, "vimalaya_new_message", true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'to: ', 'cc: ', 'bcc: ', 'subject: ' })
    last_compose_bufnr = bufnr
    enable_attachment_diagnostics(bufnr)
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

local function display_downloaded_attachment_path(download, destination)
    if not vim.api.nvim_buf_is_valid(download.bufnr) then
        return
    end
    local line = find_attachment_filename_line(download.bufnr, download.attachment_index)
    if not line then
        return
    end
    vim.api.nvim_buf_set_lines(download.bufnr, line - 1, line, false, {
        '  filename: ' .. (download.attachment.filename or '') .. ' ' .. destination,
    })
end

local function move_attachment_to_downloads(download)
    local destination_dir = resolve_download_directory()
    vim.fn.mkdir(destination_dir, 'p')
    local destination = destination_dir .. '/' .. vim.fn.fnamemodify(download.downloaded.path, ':t')
    if vim.fn.rename(download.downloaded.path, destination) ~= 0 then
        vim.fn.delete(download.temporary_dir, 'rf')
        vim.notify('Could not move attachment to ' .. destination, vim.log.levels.ERROR)
        return
    end
    vim.fn.delete(download.temporary_dir, 'rf')
    display_downloaded_attachment_path(download, destination)
end

local function process_attachment_scan_result(download, command, scan_result)
    if scan_result.code == 0 then
        move_attachment_to_downloads(download)
        return
    end

    vim.fn.delete(download.temporary_dir, 'rf')
    if scan_result.code == 1 then
        vim.notify('ClamAV detected a virus; attachment was deleted', vim.log.levels.ERROR)
        return
    end
    notify_command_failure(command, scan_result)
end

local function scan_downloaded_attachment(download)
    local command = { 'clamscan', download.downloaded.path }
    vim.system(command, {}, function(scan_result)
        vim.schedule(function()
            process_attachment_scan_result(download, command, scan_result)
        end)
    end)
end

local function process_attachment_download_result(download, result)
    if result.code ~= 0 then
        vim.fn.delete(download.temporary_dir, 'rf')
        notify_command_failure(download.command, result)
        return
    end
    if not vim.api.nvim_buf_is_valid(download.bufnr) then
        return
    end

    download.downloaded = vim.json.decode(result.stdout).attachments[1]
    if not download.downloaded or not download.downloaded.path then
        vim.fn.delete(download.temporary_dir, 'rf')
        return
    end
    scan_downloaded_attachment(download)
end

local function start_attachment_download(download)
    vim.system(download.command, {}, function(result)
        vim.schedule(function()
            process_attachment_download_result(download, result)
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

local function download_attachment_at_cursor(message, attachments)
    local attachment_index = find_attachment_index_at_cursor(message.bufnr, attachments)
    if not attachment_index then
        return
    end
    if vim.fn.executable('clamscan') == 0 then
        vim.notify('ClamAV antivirus is not installed; attachments cannot be downloaded', vim.log.levels.ERROR)
        return
    end

    local attachment = attachments[attachment_index]
    local temporary_dir = vim.fn.tempname()
    vim.fn.mkdir(temporary_dir, 'p')
    start_attachment_download({
        bufnr = message.bufnr,
        attachment_index = attachment_index,
        attachment = attachment,
        temporary_dir = temporary_dir,
        command = {
            'himalaya', 'attachment', 'download', '--mailbox', message.mailbox, '--json', message.id,
            attachment.id, '--dir', temporary_dir,
        },
    })
end

local function display_attachments(bufnr, attachments)
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
end

local function enable_attachment_downloads(message, attachments)
    vim.keymap.set('n', '<CR>', function()
        download_attachment_at_cursor(message, attachments)
    end, { buffer = message.bufnr })
end

local function process_attachment_list_result(message, command, result)
    if result.code ~= 0 then
        notify_command_failure(command, result)
        return
    end
    if not vim.api.nvim_buf_is_valid(message.bufnr) then
        return
    end

    local attachments = vim.json.decode(result.stdout).attachments
    if #attachments == 0 then
        return
    end
    display_attachments(message.bufnr, attachments)
    enable_attachment_downloads(message, attachments)
end

local function request_attachment_list(message)
    local command = { 'himalaya', 'attachment', 'list', '--mailbox', message.mailbox, '--json', message.id }
    vim.system(command, {}, function(result)
        vim.schedule(function()
            process_attachment_list_result(message, command, result)
        end)
    end)
end

local function display_message(message, command, result)
    if result.code ~= 0 then
        notify_command_failure(command, result)
        return false
    end
    if not vim.api.nvim_buf_is_valid(message.bufnr) then
        return false
    end

    local lines = vim.split(result.stdout, '\n', { plain = true })
    if lines[#lines] == '' then
        table.remove(lines)
    end

    vim.api.nvim_buf_set_lines(message.bufnr, 0, -1, false, lines)
    return true
end

local function process_message_read_result(message, command, result)
    if not display_message(message, command, result) then
        return
    end
    request_attachment_list(message)
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

    local message = { bufnr = bufnr, mailbox = mailbox, id = tostring(id) }
    local command = { 'himalaya', 'message', 'read', '--mailbox', mailbox, id }
    vim.system(command, {}, function(result)
        vim.schedule(function()
            process_message_read_result(message, command, result)
        end)
    end)
end

local function open_message_at_cursor(mailbox, envelopes)
    local line = vim.fn.line('.')
    local envelope = envelopes[line]
    M.open_message(mailbox, envelope.id, envelope.subject)
end

local function display_envelopes(bufnr, envelopes)
    local lines = {}
    for _, envelope in ipairs(envelopes) do
        table.insert(lines, envelope.date .. ' ' .. envelope.subject)
    end
    replace_readonly_buffer_lines(bufnr, lines)
end

local function enable_message_opening(bufnr, mailbox, envelopes)
    vim.keymap.set('n', '<CR>', function()
        open_message_at_cursor(mailbox, envelopes)
    end, { buffer = bufnr })
end

local function process_envelope_list_result(bufnr, mailbox, command, result)
    if result.code ~= 0 then
        notify_command_failure(command, result)
        return
    end
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end

    local envelopes = vim.json.decode(result.stdout)
    display_envelopes(bufnr, envelopes.envelopes)
    enable_message_opening(bufnr, mailbox, envelopes.envelopes)
end

local function request_envelope_list(bufnr, mailbox)
    local command = { 'himalaya', 'envelope', 'list', '--mailbox', mailbox, '--json', '--page-size', '100' }
    vim.system(command, {}, function(result)
        vim.schedule(function()
            process_envelope_list_result(bufnr, mailbox, command, result)
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

local function display_mailbox_list(bufnr, command, result)
    if result.code ~= 0 then
        notify_command_failure(command, result)
        return
    end
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end

    local mailboxes = vim.json.decode(result.stdout)
    local lines = {}
    for _, mailbox in ipairs(mailboxes.mailboxes) do
        table.insert(lines, mailbox.name)
    end

    replace_readonly_buffer_lines(bufnr, lines)
end

local function request_mailbox_list(bufnr)
    local command = { 'himalaya', 'mailbox', 'list', '--json' }
    vim.system(command, {}, function(result)
        vim.schedule(function()
            display_mailbox_list(bufnr, command, result)
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
            name = name:lower()
            headers[name] = headers[name] or {}
            table.insert(headers[name], value)
        end
    end

    local action = response_actions[kind]
    local form = { '', '', '--- ' .. action.title .. ' ---' }
    for _, value in ipairs(headers.from or { '' }) do
        table.insert(form, 'to: ' .. value)
    end
    for _, value in ipairs(headers.cc or { '' }) do
        table.insert(form, 'cc: ' .. value)
    end
    table.insert(form, 'bcc: ')
    table.insert(form, 'subject: ' .. action.subject .. ((headers.subject or {})[1] or ''))
    table.insert(form, '')
    vim.api.nvim_buf_set_lines(0, -1, -1, false, form)
    last_compose_bufnr = vim.api.nvim_get_current_buf()
    enable_attachment_diagnostics(last_compose_bufnr)
end

local function compress_directory(directory)
    local parent = vim.fn.fnamemodify(directory, ':h')
    local name = vim.fn.fnamemodify(directory, ':t')
    local archive = directory .. '.tar.gz'
    local command = { 'tar', '-czf', archive, '-C', parent, name }
    compressing_archives[archive] = true
    vim.system(command, {}, function(result)
        vim.schedule(function()
            compressing_archives[archive] = nil
            if result.code ~= 0 then
                notify_command_failure(command, result)
            end
            if last_compose_bufnr and vim.api.nvim_buf_is_valid(last_compose_bufnr) then
                M.refresh_attachment_diagnostics(last_compose_bufnr)
            end
        end)
    end)
    return archive
end

function M.attach_paths_to_message(paths, new_message)
    paths = vim.tbl_map(function(path)
        return (vim.fn.fnamemodify(path, ':p'):gsub('/$', ''))
    end, paths)

    for _, path in ipairs(paths) do
        if vim.fn.filereadable(path) ~= 1 and vim.fn.isdirectory(path) ~= 1 then
            vim.notify(':Mail cannot attach ' .. path .. ': not a file', vim.log.levels.ERROR)
            return
        end
    end

    if new_message or not last_compose_bufnr or not vim.api.nvim_buf_is_valid(last_compose_bufnr) then
        M.open_new_message_buffer()
    end

    local lines = vim.api.nvim_buf_get_lines(last_compose_bufnr, 0, -1, false)
    local attachments = vim.tbl_map(function(path)
        if vim.fn.isdirectory(path) == 1 then
            return 'attach: ' .. compress_directory(path)
        end
        return 'attach: ' .. path
    end, paths)

    local function insert_attachments(start, stop)
        vim.api.nvim_buf_set_lines(last_compose_bufnr, start, stop, false, attachments)
        M.refresh_attachment_diagnostics(last_compose_bufnr)
    end

    for index = #lines, 1, -1 do
        if lines[index] == 'attach: ' then
            insert_attachments(index - 1, index)
            return
        elseif vim.startswith(lines[index], 'attach: ') then
            insert_attachments(index, index)
            return
        end
    end

    local compose_start = (find_last_response_start(lines) or 0) + 1

    local insert_at = #lines
    for index = compose_start, #lines do
        if lines[index] == '' then
            insert_at = index - 1
            break
        end
    end
    insert_attachments(insert_at, insert_at)
end

local function process_message_send_result(send, result)
    if result.code ~= 0 then
        notify_command_failure(send.command, result)
        return
    end

    if vim.trim(result.stdout) == 'Message successfully sent' and vim.api.nvim_buf_is_valid(send.bufnr) then
        if send.is_new_message then
            vim.api.nvim_buf_delete(send.bufnr, { force = true })
        else
            vim.api.nvim_buf_set_lines(send.bufnr, send.response_start - 3, -1, false, {})
        end
    end
    vim.notify(vim.trim(result.stdout))
end

local function add_message_header(headers, name, value)
    if not name then
        return headers
    end

    name = name:lower()
    if type(headers[name]) ~= 'table' then
        headers[name] = value
        return headers
    end
    if value ~= '' then
        table.insert(headers[name], value)
    end
    return headers
end

local function extract_email_address(value)
    return value:match('<%s*(.-)%s*>') or value
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
    local response_start = is_new_message and 0 or find_last_response_start(lines)
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
        headers = add_message_header(headers, name, value)
    end

    local command = { 'himalaya', 'message', 'compose' }
    local email = find_default_account_email()
    if email then
        vim.list_extend(command, { '--from', email })
    end
    for _, name in ipairs({ 'to', 'cc', 'bcc' }) do
        for _, value in ipairs(headers[name]) do
            vim.list_extend(command, { '--' .. name, extract_email_address(value) })
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

    local send = {
        command = command,
        bufnr = bufnr,
        is_new_message = is_new_message,
        response_start = response_start,
    }
    vim.system(command, {}, function(result)
        vim.schedule(function()
            process_message_send_result(send, result)
        end)
    end)
end

function M.can_send()
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local response_start = find_last_response_start(lines)
    if not response_start then
        return false
    end

    local fields = {}
    for index = response_start + 1, #lines do
        if lines[index] == '' then
            break
        end

        local name = lines[index]:match('^([^:]+):')
        if name then
            fields[name:lower()] = true
        end
    end
    return fields.to and fields.cc and fields.subject
end

function M.refresh_attachment_diagnostics(bufnr)
    local diagnostics = {}
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    for index, line in ipairs(lines) do
        local path = line:match('^attach:%s*(.+)$')
        if path and compressing_archives[path] then
            table.insert(diagnostics, {
                lnum = index - 1,
                col = 0,
                severity = vim.diagnostic.severity.INFO,
                message = 'compressing directory into archive: ' .. path,
            })
        end
        if path and vim.fn.filereadable(vim.fn.fnamemodify(path, ':p')) ~= 1 then
            table.insert(diagnostics, {
                lnum = index - 1,
                col = 0,
                severity = vim.diagnostic.severity.WARN,
                message = 'attached file does not exist: ' .. path,
            })
        end
    end
    vim.diagnostic.set(attachment_diagnostics_namespace, bufnr, diagnostics)
end

function enable_attachment_diagnostics(bufnr)
    vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI', 'BufWritePost' }, {
        buffer = bufnr,
        callback = function()
            M.refresh_attachment_diagnostics(bufnr)
        end,
    })
    M.refresh_attachment_diagnostics(bufnr)
end

return M
