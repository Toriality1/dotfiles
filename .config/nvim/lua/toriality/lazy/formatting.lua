local prettier = { "prettierd", "prettier", stop_after_first = true }

return {
  "stevearc/conform.nvim",
  keys = {
    {
      "<leader>f",
      function()
        require("conform").format({ async = true, lsp_format = "fallback" })
      end,
      mode = { "n", "v" },
      desc = "Format file or range",
    },
  },
  opts = {
    formatters_by_ft = {
      lua = { "stylua" },
      html = prettier,
      css = prettier,
      javascript = prettier,
      javascriptreact = prettier,
      typescript = prettier,
      typescriptreact = prettier,
      astro = prettier,
      markdown = prettier,
      json = prettier,
      yaml = prettier,
      graphql = prettier,
      php = { "pint" },
      blade = { "blade-formatter" },
    },
  },
}
