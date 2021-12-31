if empty(glob('~/.vim/autoload/plug.vim'))
  silent !curl -fLo ~/.vim/autoload/plug.vim --create-dirs
    \ https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
  autocmd VimEnter * PlugInstall --sync | source ~/.vimrc
endif

call plug#begin('~/.vim/plugged')

" The best
Plug 'fatih/vim-go', { 'do': ':GoUpdateBinaries' }

" The basics
Plug 'tpope/vim-fugitive' " git wrapper
Plug 'ctrlpvim/ctrlp.vim' " search for files
Plug 'vim-airline/vim-airline' " nice looking status bar
Plug 'vim-airline/vim-airline-themes' " nice looking status bar
Plug 'edkolev/tmuxline.vim' " nice looking tmux status bar
" Plug 'dense-analysis/ale' " linter, mostly to get this:
" https://github.com/btford/write-good

" HTML/CSS/JS plugins
Plug 'alvan/vim-closetag' " closes matching HTML tags

" All of your Plugins must be added before the following line
call plug#end()            " required

set nocompatible
set encoding=utf-8
set showcmd
set ruler
set clipboard=unnamed
set tabstop=2
set shiftwidth=2
set softtabstop=2
set expandtab
set backspace=2
set autoindent
set cursorline
set hlsearch                    " highlight matches
set incsearch                   " incremental searching
set ignorecase                  " searches are case insensitive...
set laststatus=2                " something about vim-airline
set noshowmode
set noerrorbells visualbell t_vb= "turn off annoying bells
set ttyfast                     " when key repeat rate is really fast, keep up!
set hidden                      " Hide a buffer when it is abandoned.
" Open new split panes to right and bottom, which feels more natural
set splitbelow
set splitright
set backupdir=~/.vim/backup//
set directory=~/.vim/swap//
set undodir=~/.vim/undo//
syntax on
set nocursorcolumn
set nocursorline
set background=dark
colorscheme nofrils-dark
"colorscheme brianfoshee
" https://vi.stackexchange.com/questions/16148/slow-vim-escape-from-insert-mode
set timeoutlen=1000
set ttimeoutlen=5

" Set spacebar to leader
let mapleader = "\<Space>"

" Disable arrow keys
nnoremap <up>    <nop>
nnoremap <down>  <nop>
nnoremap <left>  <nop>
nnoremap <right> <nop>
inoremap <up>    <nop>
inoremap <down>  <nop>
inoremap <left>  <nop>
inoremap <right> <nop>

" https://vonheikemen.github.io/devlog/tools/using-netrw-vim-builtin-file-explorer/
" open Netrw in the directory of the current file
nnoremap <leader>dd :Lexplore %:p:h<CR>
" open Netrw in the current working directory
nnoremap <Leader>da :Lexplore<CR>

" Enable spell checking for certain filetypes
" autocmd FileType gitcommit setlocal spell
" Turn on syntax highlighting for git commits
" autocmd FileType gitcommit syntax on

" Set ignore list
set wildignore+=Godeps/_workspace/**,**/_site/**,**/bower_components/**,**/node_modules/**,**/vendor/**,**/tmp/**,*.o,*.out,*.log,**/cookbooks/**,*.swp,*.swo

" This overrides wildignore when using ctrlp
let g:ctrlp_user_command = 'ag %s --ignore-case --skip-vcs-ignores --nocolor --nogroup --hidden
      \ --ignore ".git/"
      \ --ignore ".svn/"
      \ --ignore ".hg/"
      \ --ignore ".vagrant/"
      \ --ignore ".cache/"
      \ --ignore ".gem/"
      \ --ignore ".config/"
      \ --ignore ".node-gyp/"
      \ --ignore ".npm/"
      \ --ignore ".particledev/"
      \ --ignore "Godeps/_workspace/"
      \ --ignore "_site/"
      \ --ignore "bower_components/"
      \ --ignore "node_modules/"
      \ --ignore ".DS_Store"
      \ --ignore "*.o"
      \ --ignore "*.out"
      \ --ignore "*.swp"
      \ --ignore "*.swo"
      \ --ignore "*.pyc"
      \ --ignore "vendor/"
      \ --ignore "tmp/"
      \ --ignore "dist/"
      \ -g ""'

let g:ctrlp_map = '<leader>p'
let g:ctrlp_cmd = 'CtrlP'
" ctrl-p only search the current directory, not the entire git parent
" directory
" let g:ctrlp_working_path_mode = 'c'

" <Ctrl-l> redraws the screen and removes any search highlighting.
nnoremap <silent> <C-l> :nohl<CR><C-l>
" Repeat last command
vnoremap . :norm.<CR>
" Open ECMAScript 6 files as javascript filetypes
au BufNewFile,BufRead *.es6 set filetype=javascript

" Open a new empty buffer
nmap <leader>T :enew<CR>
nmap <leader>bq :bp <BAR> bd #<CR>
nmap <leader>l :bnext<CR>
nmap <leader>h :bprevious<CR>

" any .md files are markdown files
autocmd BufNewFile,BufReadPost *.md set filetype=markdown
" Wrap text at 80 chars for markdown files
au BufRead,BufNewFile *.md setlocal textwidth=80

" Autocommand to run git stripspace on file save
au BufWritePre,FileWritePre * let b:winview = winsaveview() | let b:tmpundofile=tempname() | exe 'wundo! ' . b:tmpundofile
au BufWritePre * :silent %!git stripspace
au BufWritePost,FileWritePost * if exists('b:tmpundofile') | silent! exe 'rundo ' . b:tmpundofile | call delete(b:tmpundofile) | endif | if exists('b:winview') | call winrestview(b:winview) | unlet! b:winview | endif

" Use fonts
let g:airline_powerline_fonts = 0
let g:airline#extensions#branch#enabled = 1
let g:airline_theme = 'powerlineish'
if !exists('g:airline_symbols')
  let g:airline_symbols = {}
endif
" unicode symbols
let g:airline_left_sep = ''
let g:airline_right_sep = ''
let g:airline_symbols.linenr = '¶'
let g:airline_symbols.branch = '⎇'
let g:airline_symbols.paste = 'ρ'
let g:airline_symbols.whitespace = 'Ξ'
" Don't override .tmuxline-snapshot
let g:airline#extensions#tmuxline#enabled = 0
let g:tmuxline_powerline_separators = 0

" Setup closetag.vim to only work with html files
let g:closetag_filenames = '*.html,*.hbs'

" use go formatting
autocmd FileType go setlocal tabstop=4 softtabstop=4 shiftwidth=4 noexpandtab

" Setup vim-go to automatically import paths
let g:go_fmt_command = "goimports"
" use gopls
let g:go_def_mode='gopls'
let g:go_info_mode='gopls'
au FileType go nmap <leader>d :GoDef<CR>
au FileType go nmap <leader>ga :GoAlternate<CR>
au FileType go nmap <leader>gd :GoDecls<CR>
