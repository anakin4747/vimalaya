vim.api.nvim_create_user_command('Mail', function(options)
    local vimalaya = require('vimalaya')
    if options.range > 0 then
        local paths = vim.api.nvim_buf_get_lines(0, options.line1 - 1, options.line2, false)
        vimalaya.attach_paths(paths, options.args == 'new')
        return
    end

    local subcommands = { 'close', 'new' }
    if pcall(vim.api.nvim_buf_get_var, 0, 'vimalaya_main_menu')
        or pcall(vim.api.nvim_buf_get_var, 0, 'vimalaya_mailbox') then
        table.insert(subcommands, 'refresh')
    end
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
    elseif options.args == 'refresh' then
        vimalaya.refresh()
    else
        vimalaya.open_main_menu()
    end
end, {
    nargs = '?',
    range = true,
    complete = function(arg_lead)
        local subcommands = { 'close' }
        if pcall(vim.api.nvim_buf_get_var, 0, 'vimalaya_main_menu')
            or pcall(vim.api.nvim_buf_get_var, 0, 'vimalaya_mailbox') then
            table.insert(subcommands, 'refresh')
        end
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
            local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
            local response_start
            for index, line in ipairs(lines) do
                if response_markers[line] then
                    response_start = index
                end
            end
            local fields = {}
            for index = (response_start or #lines) + 1, #lines do
                if lines[index] == '' then
                    break
                end

                local name = lines[index]:match('^([^:]+):')
                if name then
                    fields[name:lower()] = true
                end
            end
            can_send = response_start ~= nil and fields.to and fields.cc and fields.subject
        end
        if can_send then
            table.insert(subcommands, 'send')
        end

        return vim.tbl_filter(function(subcommand)
            return vim.startswith(subcommand, arg_lead)
        end, subcommands)
    end,
})
