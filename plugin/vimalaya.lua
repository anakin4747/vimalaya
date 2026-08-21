vim.api.nvim_create_user_command('Mail', function(options)
    local vimalaya = require('vimalaya')
    if options.args == 'close' then
        vimalaya.close()
    else
        vimalaya.open_main_menu()
    end
end, { nargs = '?' })
