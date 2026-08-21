local M = {}

local main_menu_name = "vimalaya main menu"

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
    vim.api.nvim_buf_set_name(bufnr, main_menu_name)
    vim.api.nvim_buf_set_var(bufnr, "vimalaya_main_menu", true)
    vim.bo[bufnr].readonly = true
    vim.api.nvim_set_current_buf(bufnr)

    vim.system({ 'himalaya', 'mailbox', 'list', '--json' }, {}, function(result)
        if result.code ~= 0 or not vim.api.nvim_buf_is_valid(bufnr) then
            return
        end

        local mailboxes = vim.json.decode(result.stdout)
        local lines = {}
        for _, mailbox in ipairs(mailboxes.mailboxes) do
            table.insert(lines, mailbox.name)
        end

        vim.schedule(function()
            if vim.api.nvim_buf_is_valid(bufnr) then
                vim.bo[bufnr].readonly = false
                vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
                vim.bo[bufnr].readonly = true
            end
        end)
    end)
end

return M
