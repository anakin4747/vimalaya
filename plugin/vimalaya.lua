local function available_subcommands(include_send)
    local subcommands = { 'close', 'new' }
    if pcall(vim.api.nvim_buf_get_var, 0, 'vimalaya_main_menu')
        or pcall(vim.api.nvim_buf_get_var, 0, 'vimalaya_mailbox') then
        table.insert(subcommands, 'refresh')
    end
    if pcall(vim.api.nvim_buf_get_var, 0, 'vimalaya_message_id') then
        vim.list_extend(subcommands, { 'forward', 'reply', 'replyall' })
    end
    if include_send then
        table.insert(subcommands, 'send')
    end
    return subcommands
end

vim.api.nvim_create_user_command('Mail', function(options)
    local vimalaya = require('vimalaya')
    if options.range > 0 then
        local paths = vim.api.nvim_buf_get_lines(0, options.line1 - 1, options.line2, false)
        vimalaya.attach_paths_to_message(paths, options.args == 'new')
        return
    end

    local subcommands = available_subcommands(false)
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
        vimalaya.close_all_mail_buffers()
    elseif options.args == 'new' then
        vimalaya.open_new_message_buffer()
    elseif options.args == 'reply' or options.args == 'replyall' or options.args == 'forward' then
        vimalaya.append_response_form(options.args)
    elseif options.args == 'send' then
        vimalaya.send_composed_message()
    elseif options.args == 'refresh' then
        vimalaya.refresh_current_mail_view()
    else
        vimalaya.open_main_menu_buffer()
    end
end, {
    nargs = '?',
    range = true,
    complete = function(arg_lead)
        local vimalaya = require('vimalaya')
        local can_send = pcall(vim.api.nvim_buf_get_var, 0, 'vimalaya_new_message')
        if not can_send then
            can_send = vimalaya.current_response_has_required_fields()
        end
        local subcommands = available_subcommands(can_send)

        return vim.tbl_filter(function(subcommand)
            return vim.startswith(subcommand, arg_lead)
        end, subcommands)
    end,
})
