" set the runtime path to include Vundle and initialize
set rtp+=~/.vim/bundle/Vundle.vim
call vundle#begin()
" let Vundle manage Vundle, required
Plugin 'gmarik/Vundle.vim'

" The basics
Plugin 'kien/ctrlp.vim' " search for files
Plugin 'tpope/vim-fugitive' " git wrapper
Plugin 'bling/vim-airline' " nice looking status bar
Plugin 'edkolev/tmuxline.vim' " nice looking tmux status bar

Plugin 'fatih/vim-go' " the best
Plugin 'sirtaj/vim-openscad'

" Ruby plugins
Plugin 'vim-ruby/vim-ruby'
Plugin 'tpope/vim-endwise' " adds end to Ruby statements
" Rails Plugins
Plugin 'tpope/vim-rails'
Plugin 'tpope/vim-haml'
Plugin 'kchmck/vim-coffee-script'

" HTML/CSS/JS plugins
Plugin 'gorodinskiy/vim-coloresque' " highlights CSS hex/rgb colors
Plugin 'pangloss/vim-javascript'
Plugin 'mustache/vim-mustache-handlebars'
Plugin 'docunext/closetag.vim' " closes a matching html tag

" All of your Plugins must be added before the following line
call vundle#end()            " required
filetype plugin indent on    " required

set nocompatible
set encoding=utf-8
set showcmd
"set number
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
set smartcase                   " ... unless they contain at least one capital letter
set laststatus=2                " something about vim-airline
set noshowmode
set noerrorbells visualbell t_vb= "turn off annoying bells
set ttyfast                     " when key repeat rate is really fast, keep up!
set hidden
" Open new split panes to right and bottom, which feels more natural
set splitbelow
set splitright
set backupdir=~/.vim/backup//
set directory=~/.vim/swap//
set undodir=~/.vim/undo//
"folding settings
"set foldmethod=syntax
"set foldnestmax=10      "deepest fold is 10 levels
"set nofoldenable        "dont fold by default
"set foldlevel=1         "this is just what i use
syntax on
colorscheme crakalakin

" Set spacebar to leader
let mapleader = "\<Space>"

function! s:Highlight_Matching_Pair()
endfunction

" Set ignore list
set wildignore+=Godeps/_workspace/**,**/_site/**,**/bower_components/**,**/node_modules/**,**/vendor/assets/components/**,**/tmp/**,*.o,*.out,*.log,**/cookbooks/**,*.swp,*.swo

" This overrides wildignore
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
      \ -g ""'

let g:ctrlp_map = '<leader>p'
let g:ctrlp_cmd = 'CtrlP'

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
" Enable spellchecking for Markdown
" autocmd FileType markdown setlocal spell

" Autocommand to run git stripspace on file save
au BufWritePre,FileWritePre * let b:winview = winsaveview() | let b:tmpundofile=tempname() | exe 'wundo! ' . b:tmpundofile
au BufWritePre * :silent %!git stripspace
au BufWritePost,FileWritePost * if exists('b:tmpundofile') | silent! exe 'rundo ' . b:tmpundofile | call delete(b:tmpundofile) | endif | if exists('b:winview') | call winrestview(b:winview) | unlet! b:winview | endif

" Use fonts
let g:airline_powerline_fonts = 0
let g:airline#extensions#branch#enabled = 1
let g:airline_theme = 'papercolor'
if !exists('g:airline_symbols')
  let g:airline_symbols = {}
endif
" unicode symbols
let g:airline_left_sep = '»'
let g:airline_left_sep = '▶'
let g:airline_right_sep = '«'
let g:airline_right_sep = '◀'
let g:airline_symbols.linenr = '␊'
let g:airline_symbols.linenr = '␤'
let g:airline_symbols.linenr = '¶'
let g:airline_symbols.branch = '⎇'
let g:airline_symbols.paste = 'ρ'
let g:airline_symbols.paste = 'Þ'
let g:airline_symbols.paste = '∥'
let g:airline_symbols.whitespace = 'Ξ'
" Don't override .tmuxline-snapshot
let g:airline#extensions#tmuxline#enabled = 0
let g:tmuxline_powerline_separators = 0

" Setup closetag.vim to only work with html files
autocmd FileType html,xml let b:closetag_html_style=1
au Filetype html,xml source ~/.vim/bundle/closetag.vim/plugin/closetag.vim

" use go formatting
autocmd FileType go setlocal ts=8 sts=8 sw=8 noexpandtab

" Setup vim-go to automatically import paths
let g:go_fmt_command = "goimports"
