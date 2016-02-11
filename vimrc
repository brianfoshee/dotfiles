" set the runtime path to include Vundle and initialize
set rtp+=~/.vim/bundle/Vundle.vim
call vundle#begin()
" let Vundle manage Vundle, required
Plugin 'gmarik/Vundle.vim'

" The basics
Plugin 'kien/ctrlp.vim' " search for files
Plugin 'tpope/vim-fugitive' " git wrapper
Plugin 'vim-airline/vim-airline' " nice looking status bar
Plugin 'vim-airline/vim-airline-themes' " nice looking status bar

Plugin 'edkolev/tmuxline.vim' " nice looking tmux status bar

Plugin 'majutsushi/tagbar' " ctags in a sidebar

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
"Plugin 'gorodinskiy/vim-coloresque' " highlights CSS hex/rgb colors
Plugin 'pangloss/vim-javascript'
Plugin 'mustache/vim-mustache-handlebars'
Plugin 'docunext/closetag.vim' " closes a matching html tag

Plugin 'editorconfig/editorconfig-vim' " http://editorconfig.org/
Plugin 'flazz/vim-colorschemes'

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
set hidden                      " Hide a buffer when it is abandoned.
" Open new split panes to right and bottom, which feels more natural
set splitbelow
set splitright
set backupdir=~/.vim/backup//
set directory=~/.vim/swap//
set undodir=~/.vim/undo//
set tags+=tags;$HOME/
"folding settings
"set foldmethod=syntax
"set foldnestmax=10      "deepest fold is 10 levels
"set nofoldenable        "dont fold by default
"set foldlevel=1         "this is just what i use
syntax off
colorscheme crakalakin

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

" Enable spell checking for certain filetypes
autocmd FileType gitcommit setlocal spell
autocmd FileType gitcommit syntax on

" go language ctags
let g:tagbar_type_go = {
    \ 'ctagstype' : 'go',
    \ 'kinds'     : [
        \ 'p:package',
        \ 'i:imports:1',
        \ 'c:constants',
        \ 'v:variables',
        \ 't:types',
        \ 'n:interfaces',
        \ 'w:fields',
        \ 'e:embedded',
        \ 'm:methods',
        \ 'r:constructor',
        \ 'f:functions'
    \ ],
    \ 'sro' : '.',
    \ 'kind2scope' : {
        \ 't' : 'ctype',
        \ 'n' : 'ntype'
    \ },
    \ 'scope2kind' : {
        \ 'ctype' : 't',
        \ 'ntype' : 'n'
    \ },
    \ 'ctagsbin'  : 'gotags',
    \ 'ctagsargs' : '-sort -silent'
\ }

" Generate ctags on save
"au BufWritePost *.go silent! !ctags -R &

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
      \ --ignore "build/"
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

" Open Tagbag with leader-tb
nmap <leader>tb :TagbarToggle<CR>

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
"let g:airline_theme = 'papercolor'
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
autocmd FileType html,xml let b:closetag_html_style=1
au Filetype html,xml source ~/.vim/bundle/closetag.vim/plugin/closetag.vim

" use go formatting
autocmd FileType go setlocal tabstop=4 softtabstop=4 shiftwidth=4 noexpandtab

" Setup vim-go to automatically import paths
let g:go_fmt_command = "goimports"
let g:go_highlight_functions = 1
let g:go_highlight_methods = 1
let g:go_highlight_structs = 1
let g:go_highlight_operators = 1
let g:go_highlight_build_constraints = 1
au FileType go nmap <leader>d :GoDef<CR>

"let g:syntastic_go_checkers = ['golint', 'govet', 'errcheck']
"let g:syntastic_mode_map = { 'mode': 'active', 'passive_filetypes': ['go'] }
au FileType go nmap <Leader>s <Plug>(go-implements)
au FileType go nmap <Leader>i <Plug>(go-info)
au FileType go nmap <Leader>e <Plug>(go-rename)
au FileType go nmap <leader>r <Plug>(go-run)
au FileType go nmap <leader>b <Plug>(go-build)
au FileType go nmap <leader>t <Plug>(go-test)
au FileType go nmap <Leader>gd <Plug>(go-doc)
au FileType go nmap <Leader>gv <Plug>(go-doc-vertical)
au FileType go nmap <leader>co <Plug>(go-coverage)
