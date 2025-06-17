return {
    "Exafunction/windsurf.nvim",
    dependencies = {
        "nvim-lua/plenary.nvim",
        "hrsh7th/nvim-cmp",
    },
    config = function ()
        require("codeium").setup({
            virtual_text = {
                enabled = true,
                idle_delay = 500
            },
            vim.keymap.set('n', '<leader>x', '<cmd>Codeium Toggle<CR>')
        })
    end
}
