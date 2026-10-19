return {
  "lewis6991/gitsigns.nvim",
  config = function()
    require("gitsigns").setup({
      on_attach = function(bufnr)
        local gitsigns = require("gitsigns")
        local function opts(desc)
          return { buffer = bufnr, desc = desc }
        end

        -- ]c / [c already mean next/previous change in diff mode
        vim.keymap.set("n", "]c", function()
          if vim.wo.diff then
            vim.cmd.normal({ "]c", bang = true })
          else
            gitsigns.nav_hunk("next")
          end
        end, opts("Next Git hunk"))
        vim.keymap.set("n", "[c", function()
          if vim.wo.diff then
            vim.cmd.normal({ "[c", bang = true })
          else
            gitsigns.nav_hunk("prev")
          end
        end, opts("Previous Git hunk"))

        vim.keymap.set("n", "<leader>gp", gitsigns.preview_hunk, opts("Preview Git hunk"))
        vim.keymap.set("n", "<leader>gb", function()
          gitsigns.blame_line({ full = true })
        end, opts("Show line blame"))
      end,
    })
  end,
}
