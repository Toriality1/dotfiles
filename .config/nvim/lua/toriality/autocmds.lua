local group = vim.api.nvim_create_augroup("Toriality", { clear = true })
local autocmd = vim.api.nvim_create_autocmd

autocmd("TextYankPost", {
  group = group,
  callback = function()
    vim.hl.on_yank({ higroup = "IncSearch", timeout = 40 })
  end,
})

autocmd("FileType", {
  group = group,
  pattern = "c",
  callback = function(event)
    vim.keymap.set("n", "<leader><leader>", function()
      local filename = vim.api.nvim_buf_get_name(0)
      if filename == "" or vim.fn.executable("gcc") ~= 1 then
        vim.notify("Save the file and install gcc before running C code", vim.log.levels.WARN)
        return
      end

      vim.cmd.write()
      local executable = vim.fn.fnamemodify(filename, ":r")
      if executable == filename then
        executable = filename .. ".out"
      end
      local command = "gcc "
        .. vim.fn.shellescape(filename)
        .. " -o "
        .. vim.fn.shellescape(executable)
        .. " && "
        .. vim.fn.shellescape(executable)
      vim.cmd("botright new")
      vim.fn.jobstart(command, { term = true, cwd = vim.fs.dirname(filename) })
    end, { buffer = event.buf, desc = "Compile and run C file" })
  end,
})

autocmd("FileType", {
  group = group,
  pattern = "lua",
  callback = function(event)
    vim.keymap.set("n", "<leader><leader>", "<cmd>source<CR>", {
      buffer = event.buf,
      desc = "Source Lua file",
    })
  end,
})

autocmd("FileType", {
  group = group,
  pattern = "gdscript",
  callback = function(event)
    local root = vim.fs.root(event.buf, "project.godot")
    if root then
      vim.lsp.start({
        name = "godot",
        cmd = vim.lsp.rpc.connect("127.0.0.1", 6005),
        root_dir = root,
      }, { bufnr = event.buf })
    end
  end,
})

autocmd("FileType", {
  group = group,
  pattern = "blade",
  callback = function(event)
    vim.bo[event.buf].commentstring = "{{-- %s --}}"
  end,
})

autocmd("BufWritePre", {
  group = group,
  callback = function(event)
    local options = vim.bo[event.buf]
    -- Markdown uses trailing spaces for hard line breaks.
    if
      not options.modifiable
      or options.readonly
      or options.buftype ~= ""
      or options.filetype == "markdown"
    then
      return
    end
    local view = vim.fn.winsaveview()
    vim.cmd([[keeppatterns %s/\s\+$//e]])
    vim.fn.winrestview(view)
  end,
})

autocmd("LspAttach", {
  group = group,
  callback = function(event)
    local function map(lhs, rhs, desc)
      vim.keymap.set("n", lhs, rhs, { buffer = event.buf, desc = desc })
    end
    map("gd", vim.lsp.buf.definition, "Go to definition")
    map("gh", vim.lsp.buf.hover, "Show hover documentation")
    map("<leader>vws", vim.lsp.buf.workspace_symbol, "Search workspace symbols")
    map("<leader>vd", vim.diagnostic.open_float, "Show diagnostics")
    map("<leader>vca", vim.lsp.buf.code_action, "Code action")
    map("<leader>vrr", vim.lsp.buf.references, "Find references")
    map("<leader>vrn", vim.lsp.buf.rename, "Rename symbol")
    vim.keymap.set("i", "<C-h>", vim.lsp.buf.signature_help, {
      buffer = event.buf,
      desc = "Show signature help",
    })
  end,
})

autocmd({ "BufWinEnter", "FileType", "LspAttach", "BufWritePost" }, {
  group = group,
  callback = function(event)
    require("toriality.buffer").update_folds(event.buf)
  end,
})

autocmd("LspDetach", {
  group = group,
  callback = function(event)
    -- The departing client is still attached during this event.
    vim.schedule(function()
      require("toriality.buffer").update_folds(event.buf)
    end)
  end,
})
