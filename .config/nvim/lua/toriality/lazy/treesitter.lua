return {
  {
    "nvim-treesitter/nvim-treesitter",
    -- This config uses the master API; main is an incompatible rewrite.
    branch = "master",
    build = ":TSUpdate",
    config = function()
      require("nvim-treesitter.configs").setup({
        ensure_installed = {
          "vimdoc",
          "javascript",
          "typescript",
          "c",
          "lua",
          "rust",
          "jsdoc",
          "bash",
          "go",
          "php",
          "php_only",
          "phpdoc",
          "blade",
          "html",
          "css",
          "json",
          "yaml",
          "markdown",
          "markdown_inline",
        },
        sync_install = false,
        auto_install = true,
        highlight = {
          enable = true,
          disable = function(lang, bufnr)
            return lang == "html" or require("toriality.buffer").is_large(bufnr)
          end,
          additional_vim_regex_highlighting = { "markdown" },
        },
      })
    end,
  },
  {
    "nvim-treesitter/nvim-treesitter-context",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    opts = {
      max_lines = 4,
      multiline_threshold = 20,
      on_attach = function(bufnr)
        return not require("toriality.buffer").is_large(bufnr)
      end,
    },
  },
}
