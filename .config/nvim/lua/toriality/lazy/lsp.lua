return {
  "neovim/nvim-lspconfig",
  event = { "BufReadPre", "BufNewFile" },
  dependencies = {
    "williamboman/mason.nvim",
    "williamboman/mason-lspconfig.nvim",
    "hrsh7th/cmp-nvim-lsp",
  },
  config = function()
    vim.lsp.config("*", {
      capabilities = require("cmp_nvim_lsp").default_capabilities(),
    })

    vim.lsp.config("lua_ls", {
      settings = {
        Lua = {
          format = {
            enable = true,
            defaultConfig = { indent_style = "space", indent_size = "2" },
          },
        },
      },
    })

    vim.lsp.config("intelephense", {
      settings = {
        intelephense = {
          files = { maxSize = 5000000 },
          environment = {
            includePaths = { "vendor/laravel/framework/src/Illuminate/Support" },
          },
          -- Keep the server's default stub set instead of copying its inventory.
        },
      },
    })

    vim.lsp.config("laravel_ls", { filetypes = { "php", "blade" } })

    require("mason").setup()
    require("mason-lspconfig").setup({
      ensure_installed = { "lua_ls", "intelephense", "ts_ls", "tailwindcss", "eslint" },
      automatic_enable = true,
    })
    require("toriality.tools").setup(function(name)
      if name == "laravel-ls" then
        vim.lsp.enable("laravel_ls")
      end
    end)

    vim.diagnostic.config({
      virtual_text = true,
      jump = { float = true },
      float = {
        focusable = true,
        style = "minimal",
        border = "rounded",
        source = true,
        header = "",
        prefix = "",
      },
    })
  end,
}
