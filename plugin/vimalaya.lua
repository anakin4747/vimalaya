vim.api.nvim_create_user_command('Mail', function(options)
    local vimalaya = require('vimalaya')
    local subcommands = { 'close', 'new' }
    if pcall(vim.api.nvim_buf_get_var, 0, 'vimalaya_message_id') then
        vim.list_extend(subcommands, { 'forward', 'reply', 'replyall' })
    end
    local matches = vim.tbl_filter(function(subcommand)
        return vim.startswith(subcommand, options.args)
    end, subcommands)
    if options.args ~= '' and not vim.tbl_contains(subcommands, options.args) and #matches > 1 then
        vim.notify(
            ':Mail ' .. options.args .. ' is ambiguous; possible completions: ' .. table.concat(matches, ', '),
            vim.log.levels.ERROR
        )
        return
    end

    if options.args == 'close' then
        vimalaya.close()
    elseif options.args == 'new' then
        vimalaya.open_new_message()
    elseif options.args == 'reply' or options.args == 'replyall' or options.args == 'forward' then
        vimalaya.append_response(options.args)
    elseif options.args == 'send' then
        vimalaya.send_response()
    else
        vimalaya.open_main_menu()
    end
end, {
    nargs = '?',
    complete = function(arg_lead)
        local subcommands = { 'close' }
        if pcall(vim.api.nvim_buf_get_var, 0, 'vimalaya_message_id') then
            vim.list_extend(subcommands, { 'forward', 'reply', 'replyall' })
        end
        local can_send = pcall(vim.api.nvim_buf_get_var, 0, 'vimalaya_new_message')
        if not can_send then
            local response_markers = {
                ['--- Reply ---'] = true,
                ['--- Reply All ---'] = true,
                ['--- Forward ---'] = true,
            }
            for _, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
                if response_markers[line] then
                    can_send = true
                    break
                end
            end
        end
        if can_send then
            table.insert(subcommands, 'send')
        end

        return vim.tbl_filter(function(subcommand)
            return vim.startswith(subcommand, arg_lead)
        end, subcommands)
    end,
})
