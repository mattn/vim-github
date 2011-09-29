" An interface for Github.
" Version: 0.1.0
" Author : thinca <thinca+vim@gmail.com>
" License: Creative Commons Attribution 2.1 Japan License
"          <http://creativecommons.org/licenses/by/2.1/jp/deed.en>

let s:save_cpo = &cpo
set cpo&vim

let s:domain = 'github.com'
let s:base_path = '/api/v2/json'
let s:is_win = has('win16') || has('win32') || has('win64')



let s:Base = {}  " {{{1
function! s:Base.new(...)
  let obj = copy(self)
  if has_key(obj, 'initialize')
    call call(obj.initialize, a:000, obj)
  endif
  return obj
endfunction



" API
let s:Github = s:Base.new()  " {{{1
function! s:Github.initialize(user, token)
  let [self.user, self.token] = [a:user, a:token]

  let self.curl_cmd = g:github#curl_cmd
  let self.protocol = g:github#use_https ? 'https' : 'http'
endfunction

function! s:Github.connect(path, ...)
  let params = {}
  let path = a:path
  let raw = 0
  for a in github#flatten(a:000)
    if type(a) == type(0)
      raw = a
    elseif type(a) == type('')
      let path .= '/' . a
    elseif type(a) == type({})
      call extend(params, a)
    endif
    unlet a
  endfor

  let files = []
  try
    let postdata = {'login': self.user, 'token': self.token}

    for [key, val] in items(params)
      let f = tempname()
      call add(files, f)
      call writefile(split(s:iconv(val, &encoding, 'utf-8'), "\n", 1), f, 'b')
      let postdata[key] = '<' . f
    endfor

    let param = []
    for [key, val] in items(postdata)
      let param += ['-F', key . '=' . val]
    endfor

    let res = s:system([self.curl_cmd, '-s', '-k',
    \   printf('%s://%s%s%s', self.protocol, s:domain, s:base_path, path)]
    \   + param)
  finally
    for f in files
      call delete(f)
    endfor
  endtry

  let res = s:iconv(res, 'utf-8', &encoding)

  return raw ? res : s:parse_json(res)
endfunction



" UI
let s:UI = s:Base.new()  " {{{1
function! s:UI.opened(type)
endfunction

function! s:UI.updated(type, name)
endfunction

function! s:UI.header()
  return ''
endfunction

function! s:UI.view(with, ...)
  let ft = 'github-' . self.name
  let bufnr = 0
  for i in range(0, winnr('$'))
    let n = winbufnr(i)
    if getbufvar(n, '&filetype') ==# ft
      if i != 0
        execute i 'wincmd w'
      endif
      let bufnr = n
      break
    endif
  endfor

  let name = 'view_' . a:with
  if bufnr == 0
    " TODO: Opener is made customizable.
    " FIXME: This buffer name is tentative.
    new `=printf('[github-%s:%s]', self.name, name)`

    setlocal nobuflisted
    setlocal buftype=nofile noswapfile bufhidden=wipe
    setlocal nonumber nolist nowrap

    call self.opened('view')

    let &l:filetype = ft
  else
    setlocal modifiable noreadonly
    silent % delete _
  endif

  let b:github_{self.name} = self
  let b:github_{self.name}_buf = name

  silent 0put =self.header()
  silent $put =call(self[name], a:000, self)

  1
  call self.updated('view', a:with)
  setlocal nomodifiable readonly
endfunction

function! s:UI.edit(template, ...)
  let ft = 'github-' . self.name
  let name = 'edit_' . a:template

  " TODO: Opener is made customizable.
  " FIXME: This buffer name is tentative.
  new `=printf('[github-%s:%s]', self.name, name)`
  let b:github_{self.name} = self

  setlocal nobuflisted
  setlocal buftype=nofile noswapfile bufhidden=wipe
  let &l:filetype = ft

  call self.opened('edit')

  let b:github_{self.name}_buf = name
  silent 0put =self.header()
  silent $put =call(self[name], a:000, self)

  1
  call self.updated('view', a:template)
endfunction



" Features manager.  {{{1
let s:features = {}

function! github#register(feature)
  let feature = extend(copy(s:UI), a:feature)
  let s:features[feature.name] = feature
endfunction


" Interfaces.  {{{1
function! github#base()
  return s:Base.new()
endfunction



function! github#connect(path, ...)
  return s:Github.new(g:github#user, g:github#token).connect(a:path, a:000)
endfunction



function! github#flatten(list)
  let list = []
  for i in a:list
    if type(i) == type([])
      let list += github#flatten(i)
    else
      call add(list, i)
    endif
    unlet! i
  endfor
  return list
endfunction



function! github#get_text_on_cursor(pat)
  let line = getline('.')
  let pos = col('.')
  let s = 0
  while s < pos
    let [s, e] = [match(line, a:pat, s), matchend(line, a:pat, s)]
    if s < 0
      break
    elseif s < pos && pos <= e
      return line[s : e - 1]
    endif
    let s += 1
  endwhile
  return ''
endfunction



" Main commands.  {{{1
function! github#invoke(argline)
  " The simplest implementation.
  try
    let [feat; args] = split(a:argline, '\s\+')
    if !has_key(s:features, feat)
      throw 'github: Specified feature is not registered: ' . feat
    endif
    call s:features[feat].invoke(args)
  catch /^github:/
    echohl ErrorMsg
    echomsg v:exception
    echohl None
  endtry
endfunction



function! github#complete(lead, cmd, pos)
  return keys(s:features)
endfunction



" JSON and others utilities.  {{{1
function! s:validate_json(str)
  " Reference: http://mattn.kaoriya.net/software/javascript/20100324023148.htm

  return a:str != '' &&
  \ substitute(substitute(substitute(
  \ a:str,
  \ '\\\%(["\\/bfnrt]\|u[0-9a-fA-F]\{4}\)', '\@', 'g'),
  \ '"[^\"\\\n\r]*\"\|true\|false\|null\|-\?\d\+'
  \ . '\%(\.\d*\)\?\%([eE][+\-]\{-}\d\+\)\?', ']', 'g'),
  \ '\%(^\|:\|,\)\%(\s*\[\)\+', '', 'g') =~ '^[\],:{} \t\n]*$'
endfunction



function! s:parse_json(json)
  if !s:validate_json(a:json)
    call github#debug_log("Invalid response:\n" . a:json)
    throw 'github: Invalid json.'
  endif
  let l:true = 1
  let l:false = 0
  let l:null = 0
  let json = eval(a:json)
  if g:github#debug
    call github#debug_log("response json:\n" .
    \ (exists('*PP') ? PP(json) : string(json)))
  endif
  return json
endfunction



function! s:iconv(expr, from, to)
  if a:from ==# a:to || a:from == '' || a:to == ''
    return a:expr
  endif
  let result = iconv(a:expr, a:from, a:to)
  return result != '' ? result : a:expr
endfunction


function! s:system(args)
  let type = type(a:args)
  let args = type == type([]) ? a:args :
  \          type == type('') ? split(a:args) : []

  if g:github#use_vimproc
    call github#debug_log(args)
    return vimproc#system(args)
  endif

  if s:is_win
    let args[0] = s:cmdpath(args[0])
    let q = '"'
    let cmd = q . join(map(args,
    \   'q . substitute(escape(v:val, q), "[<>^|&]", "^\\0", "g") . q'),
    \   ' ') . q
  else
    let cmd = join(map(args, 'shellescape(v:val)'), ' ')
  endif
  call github#debug_log(cmd)
  return system(cmd)
endfunction



function! s:cmdpath(cmd)
  " Search the fullpath of command for MS Windows.
  let full = glob(a:cmd)
  if a:cmd ==? full
    " Already fullpath.
    return a:cmd
  endif

  let extlist = split($PATHEXT, ';')
  if a:cmd =~? '\V\%(' . substitute($PATHEXT, ';', '\\|', 'g') . '\)\$'
    call insert(extlist, '', 0)
  endif
  for dir in split($PATH, ';')
    for ext in extlist
      let full = glob(dir . '\' . a:cmd . ext)
      if full != ''
        return full
      endif
    endfor
  endfor
  return ''
endfunction



" Debug.  {{{1
function! github#debug_log(mes, ...)
  if g:github#debug
    let mes = a:0 ? call('printf', [a:mes] + a:000) : a:mes
    if g:github#debug_file == ''
      for m in split(mes, "\n")
        echomsg 'github: ' . m
      endfor
    else
      execute 'redir >>' g:github#debug_file
      silent! echo strftime('%c:') mes
      redir END
    endif
  endif
endfunction



" Options.  {{{1
if !exists('g:github#curl_cmd')  " {{{2
  let g:github#curl_cmd = 'curl'
endif

if !exists('g:github#use_https')  " {{{2
  let g:github#use_https = 0
endif

if !exists('g:github#use_vimproc')  " {{{2
  let g:github#use_vimproc =
  \   globpath(&runtimepath, 'autoload/vimproc.vim') != ''
endif

if !exists('g:github#debug')  " {{{2
  let g:github#debug = 0
endif

if !exists('g:github#debug_file')  " {{{2
  let g:github#debug_file = ''
endif

if !exists('g:github#user')  " {{{2
  let g:github#user =
  \   matchstr(s:system('git config --global github.user'), '\w*')
endif

if !exists('g:github#token')  " {{{2
  let g:github#token =
  \   matchstr(s:system('git config --global github.token'), '\w*')
endif



" Register the default features. {{{1
function! s:register_defaults()
  let list = split(globpath(&runtimepath, 'autoload/github/*.vim'), "\n")
  for name in map(list, 'fnamemodify(v:val, ":t:r")')
    try
      call github#register(github#{name}#new())
    catch /:E\%(117\|716\):/
    endtry
  endfor
endfunction

call s:register_defaults()



let &cpo = s:save_cpo
unlet s:save_cpo
