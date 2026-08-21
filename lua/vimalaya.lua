local M = {}

local main_menu_name = "vimalaya main menu"

function M.open_message(mailbox, id)
    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(bufnr, vim.fn.tempname())
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
            for _, envelope in ipairs(envelopes.envelopes) do
                table.insert(lines, envelope.date .. ' ' .. envelope.subject)
                table.insert(envelope_ids, envelope.id)
            end

            vim.bo[bufnr].readonly = false
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
            vim.bo[bufnr].readonly = true
            vim.keymap.set('n', '<CR>', function()
                M.open_message(mailbox, envelope_ids[vim.fn.line('.')])
            end, { buffer = bufnr })
        end)
    end)
end

function M.open_main_menu()
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

return M
