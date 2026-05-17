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

" HTML/CSS/JS plugins
Plug 'alvan/vim-closetag' " closes matching HTML tags

" Ruby plugin
Plug 'vim-ruby/vim-ruby'

" Terraform
Plug 'hashivim/vim-terraform'

" All of your Plugins must be added before the following line
call plug#end()            " required

set encoding=utf-8
set showcmd
set ruler
set clipboard=unnamed
set tabstop=2
set shiftwidth=2
set softtabstop=2
set expandtab
set backspace=indent,eol,start
set autoindent
set cursorline
set hlsearch                    " highlight matches
set incsearch                   " incremental searching
set ignorecase                  " case-insensitive...
set smartcase                   " ...unless the pattern has uppercase
set laststatus=2                " something about vim-airline
set noshowmode
set noerrorbells visualbell t_vb= "turn off annoying bells
set hidden                      " Hide a buffer when it is abandoned.
set scrolloff=5                 " keep 5 lines of context above/below cursor
set mouse=a                     " mouse support in all modes
" Open new split panes to right and bottom, which feels more natural
set splitbelow
set splitright
set backupdir=~/.vim/backup//
set directory=~/.vim/swap//
set undodir=~/.vim/undo//
set undofile                    " persist undo history across sessions
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

" Explore window 20%
let g:netrw_winsize = 20

" Enable spell checking for certain filetypes
" autocmd FileType gitcommit setlocal spell
" Turn on syntax highlighting for git commits
" autocmd FileType gitcommit syntax on

" Skip these in vim's built-in file completion (:edit, :find, glob()).
" rg has its own ignore mechanism via ~/.ignore + .gitignore.
set wildignore+=*.swp,*.swo,*~
set wildignore+=.git/**,**/.DS_Store
set wildignore+=**/node_modules/**,**/vendor/**,**/tmp/**

" ctrlp uses ripgrep. Project ignores live in .gitignore; cross-project
" ignores live in ~/.ignore (tracked as `ignore` in this repo).
let g:ctrlp_user_command = 'rg %s --files --hidden --glob "!.git/*"'

let g:ctrlp_map = '<leader>p'
let g:ctrlp_cmd = 'CtrlP'
" ctrl-p only search the current directory, not the entire git parent
" directory
" let g:ctrlp_working_path_mode = 'c'

" <Ctrl-l> redraws the screen and removes any search highlighting.
nnoremap <silent> <C-l> :nohl<CR><C-l>
" Repeat last command
vnoremap . :norm.<CR>

" Open a new empty buffer
nnoremap <leader>T :enew<CR>
nnoremap <leader>bq :bp <BAR> bd #<CR>
nnoremap <leader>l :bnext<CR>
nnoremap <leader>h :bprevious<CR>

" Wrap text at 80 chars for markdown files
autocmd FileType markdown setlocal textwidth=80

" Autocommand to run git stripspace on file save
augroup GitStripspace
  autocmd!

  " Define function to check if file should be processed
  function! s:ShouldStripWhitespace()
    " File types where trailing whitespace is significant or where tooling
    " exists to handle it separately.
    let excluded_extensions = ['md', 'tf', 'go']
    let current_ext = expand('%:e')
    return index(excluded_extensions, current_ext) == -1 && executable('git')
  endfunction

  " Function to safely run stripspace with error handling
  function! s:StripWhitespace()
    if !s:ShouldStripWhitespace()
      return
    endif

    " Save state
    let b:winview = winsaveview()
    let b:tmpundofile = tempname()

    try
      execute 'wundo! ' . b:tmpundofile
      silent %!git stripspace
    catch
      " Restore view on error
      if exists('b:winview')
        call winrestview(b:winview)
      endif
      " Clean up temp file on error
      if exists('b:tmpundofile') && filereadable(b:tmpundofile)
        call delete(b:tmpundofile)
      endif
      throw v:exception
    endtry
  endfunction

  " Function to restore state after write
  function! s:RestoreState()
    if exists('b:tmpundofile') && filereadable(b:tmpundofile)
      silent! execute 'rundo ' . b:tmpundofile
      call delete(b:tmpundofile)
      unlet! b:tmpundofile
    endif

    if exists('b:winview')
      call winrestview(b:winview)
      unlet! b:winview
    endif
  endfunction

  autocmd BufWritePre * call s:StripWhitespace()
  autocmd BufWritePost * call s:RestoreState()
augroup END

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
" Setup closetag.vim to only work with html files
let g:closetag_filenames = '*.html,*.html.erb'

" ─── vim-go ──────────────────────────────────────────────────────────────────

let g:go_fmt_command = "goimports"
let g:go_def_mode='gopls'
let g:go_info_mode='gopls'
au FileType go nnoremap <leader>gd :GoDef<CR>
au FileType go nnoremap <leader>gD :GoDecls<CR>
au FileType go nnoremap <leader>ga :GoAlternate<CR>
