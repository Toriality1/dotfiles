vim.g.mapleader = " "

local function map(mode, lhs, rhs, desc)
  vim.keymap.set(mode, lhs, rhs, { desc = desc })
end

map("n", "<leader>pv", vim.cmd.Ex, "Open file explorer")
map("n", "<leader>w", "<cmd>w<CR>", "Save file")
map("v", "J", ":m '>+1<CR>gv=gv", "Move selection down")
map("v", "K", ":m '<-2<CR>gv=gv", "Move selection up")
map("n", "J", "mzJ`z", "Join lines without moving cursor")
map("n", "<C-d>", "<C-d>zz", "Scroll down and center cursor")
map("n", "<C-u>", "<C-u>zz", "Scroll up and center cursor")
map("n", "n", "nzzzv", "Next search match and center cursor")
map("n", "N", "Nzzzv", "Previous search match and center cursor")
map("n", "=ap", "ma=ap'a", "Indent paragraph without moving cursor")
map("x", "<leader>p", [["_dP]], "Paste without replacing clipboard")
map({ "n", "v" }, "<leader>y", [["+y]], "Yank to system clipboard")
map("n", "<leader>Y", [["+Y]], "Yank line to system clipboard")
map({ "n", "v" }, "<leader>d", [["_d]], "Delete without replacing clipboard")
map("n", "Q", "<nop>", "Disable Ex mode")
map("n", "<C-k>", "<cmd>cnext<CR>zz", "Next quickfix entry")
map("n", "<C-j>", "<cmd>cprev<CR>zz", "Previous quickfix entry")
map("n", "<leader>k", "<cmd>lnext<CR>zz", "Next location list entry")
map("n", "<leader>j", "<cmd>lprev<CR>zz", "Previous location list entry")
map(
  "n",
  "<leader>s",
  [[:%s/\<<C-r><C-w>\>/<C-r><C-w>/gI<Left><Left><Left>]],
  "Replace word in file"
)

map("n", "<leader>td", function()
  local start = vim.api.nvim_buf_get_name(0)
  if start == "" then
    start = vim.fn.getcwd()
  end
  local root = vim.fs.root(
    start,
    { ".git", "package.json", "composer.json", "go.mod", "Cargo.toml", "project.godot" }
  ) or vim.fn.getcwd()
  vim.cmd.edit(vim.fs.joinpath(root, "todo.md"))
end, "Open project todo.md")
