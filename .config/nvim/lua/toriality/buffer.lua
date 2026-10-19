local M = {}

function M.is_large(bufnr)
  local stat = vim.uv.fs_stat(vim.api.nvim_buf_get_name(bufnr))
  return stat ~= nil and stat.size > 100 * 1024
end

function M.update_folds(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local method, expr = "manual", "0"
  if vim.bo[bufnr].buftype == "" and not M.is_large(bufnr) then
    for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
      if client:supports_method("textDocument/foldingRange") then
        method, expr = "expr", "v:lua.vim.lsp.foldexpr()"
        break
      end
    end
    if method == "manual" then
      local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
      if ok and parser then
        method, expr = "expr", "v:lua.vim.treesitter.foldexpr()"
      end
    end
  end

  for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
    vim.wo[win].foldmethod = method
    vim.wo[win].foldexpr = expr
  end
end

return M
