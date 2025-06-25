require("toriality.set")
require("toriality.remap")
require("toriality.lazy_init")

local augroup = vim.api.nvim_create_augroup
local TorialityGroup = augroup('Toriality', {})

local autocmd = vim.api.nvim_create_autocmd
local yank_group = augroup('HighlightYank', {})

function R(name)
    require("plenary.reload").reload_module(name)
end

autocmd('TextYankPost', {
    group = yank_group,
    pattern = '*',
    callback = function()
        vim.highlight.on_yank({
            higroup = 'IncSearch',
            timeout = 40,
        })
    end,
})

autocmd("FileType", {
    pattern = "c",
    callback = function()
        vim.keymap.set('n', '<leader><leader>', function()
            local filename = vim.fn.expand("%:t:r")
            vim.cmd("w")
            local cmd = "terminal gcc % -o %< && ./" .. filename
            vim.cmd(cmd)
        end)
    end
})

autocmd("FileType", {
    pattern = "lua",
    callback = function()
        vim.keymap.set('n', '<leader><leader>', ':so<CR>', { buffer = true })
    end
})

autocmd("FileType", {
    pattern = "gdscript",
    callback = function()
        vim.lsp.start({
            name = "godot",
            cmd = { "nc", "localhost", "6005" }, -- Connect to Godot's LSP server
            root_dir = vim.fs.dirname(vim.fs.find({ "project.godot" }, { upward = true })[1]),
        })
    end,
})

autocmd({ "BufWritePre" }, {
    group = TorialityGroup,
    pattern = "*",
    command = [[%s/\s\+$//e]],
})

autocmd('LspAttach', {
    group = TorialityGroup,
    callback = function(e)
        local opts = { buffer = e.buf }
        vim.keymap.set("n", "gd", function() vim.lsp.buf.definition() end, opts)
        vim.keymap.set("n", "gh", function() vim.lsp.buf.hover() end, opts)
        vim.keymap.set("n", "<leader>vws", function() vim.lsp.buf.workspace_symbol() end, opts)
        vim.keymap.set("n", "<leader>vd", function() vim.diagnostic.open_float() end, opts)
        vim.keymap.set("n", "<leader>vca", function() vim.lsp.buf.code_action() end, opts)
        vim.keymap.set("n", "<leader>vrr", function() vim.lsp.buf.references() end, opts)
        vim.keymap.set("n", "<leader>vrn", function() vim.lsp.buf.rename() end, opts)
        vim.keymap.set("i", "<C-h>", function() vim.lsp.buf.signature_help() end, opts)
        vim.keymap.set("n", "[d", function() vim.diagnostic.goto_next() end, opts)
        vim.keymap.set("n", "]d", function() vim.diagnostic.goto_prev() end, opts)
        vim.keymap.set("n", "<leader>f", function() vim.lsp.buf.format() end, opts)
    end
})

vim.g.netrw_browse_split = 0
vim.g.netrw_banner = 0
vim.g.netrw_winsize = 25
