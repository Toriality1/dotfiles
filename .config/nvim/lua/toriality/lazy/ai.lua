return {
  "Exafunction/windsurf.nvim",
  event = "InsertEnter",
  cmd = "Codeium",
  keys = {
    { "<leader>x", "<cmd>Codeium Toggle<CR>", desc = "Toggle AI completion" },
  },
  dependencies = {
    "nvim-lua/plenary.nvim",
    "hrsh7th/nvim-cmp",
  },
  config = function()
    require("codeium").setup({
      virtual_text = {
        enabled = true,
        idle_delay = 500,
      },
    })
  end,
}
