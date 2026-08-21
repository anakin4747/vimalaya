vim.api.nvim_create_user_command('Mail', function(options)
    local vimalaya = require('vimalaya')
    if options.args == 'close' then
        vimalaya.close()
    elseif options.args == 'reply' or options.args == 'replyall' or options.args == 'forward' then
        vimalaya.append_response(options.args)
    else
        vimalaya.open_main_menu()
    end
end, { nargs = '?' })
