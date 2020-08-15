" Author: liuchengxu <xuliuchengxlc@gmail.com>
" Description: Ivy-like file explorer.

scriptencoding utf-8

let s:save_cpo = &cpoptions
set cpoptions&vim

let s:filer = {}

let s:PATH_SEPERATOR = has('win32') && !(exists('+shellslash') && &shellslash) ? '\' : '/'
let s:DIRECTORY_IS_EMPTY = (g:clap_enable_icon ? '  ' : '').'Directory is empty'

function! clap#provider#filer#hi_empty_dir() abort
  syntax match ClapEmptyDirectory /^.*Directory is empty/
  hi default link ClapEmptyDirectory WarningMsg
endfunction

function! s:handle_result(result) abort
  if a:result.total == 0
    let s:filer_empty_cache[a:result.dir] = s:DIRECTORY_IS_EMPTY
    call g:clap.display.set_lines([s:DIRECTORY_IS_EMPTY])
  else
    let s:filer_cache[a:result.dir] = a:result.entries
    call g:clap.display.set_lines(a:result.entries)
  endif
  call clap#sign#reset_to_first_line()
  call clap#state#refresh_matches_count(string(a:result.total))
  call g:clap#display_win.shrink_if_undersize()
endfunction

function! clap#provider#filer#daemon_handle(decoded) abort
  if has_key(a:decoded, 'error')
    let error = a:decoded.error
    let s:filer_error_cache[error.dir] = error.message
    call g:clap.display.set_lines([error.message])
    call clap#indicator#set('[??]')
    return
  endif

  if has_key(a:decoded, 'result')
    call s:handle_result(a:decoded.result)
  else
    call clap#helper#echo_error('This should not happen, neither error nor result is found.')
  endif
endfunction

function! s:set_prompt() abort
  if strlen(s:current_dir) < s:winwidth * 3 / 4
    call clap#spinner#set(s:current_dir)
  else
    let parent = fnamemodify(s:current_dir, ':p:h')
    let last = fnamemodify(s:current_dir, ':p:t')
    let short_dir = pathshorten(parent).s:PATH_SEPERATOR.last
    if strlen(short_dir) < s:winwidth * 3 / 4
      call clap#spinner#set(short_dir)
    else
      call clap#spinner#set(pathshorten(s:current_dir))
    endif
  endif
endfunction

if has('win32')
  function! s:is_root_directory(dir) abort
    return a:dir =~? '^\([a-z]:\|\(\\\\\|\/\/\)[^\\\/]\+\(\\\|\/\/\)[^\\\/]\+\)\(\\\|\/\)\+$'
  endfunction
else
  function! s:is_root_directory(dir) abort
    return a:dir ==# s:PATH_SEPERATOR
  endfunction
endif

function! s:goto_parent() abort
  " The root directory
  if s:is_root_directory(s:current_dir)
    return
  endif

  if s:current_dir[-1:] ==# s:PATH_SEPERATOR
    let parent_dir = fnamemodify(s:current_dir, ':h:h')
  else
    let parent_dir = fnamemodify(s:current_dir, ':h')
  endif

  if s:is_root_directory(parent_dir)
    let s:current_dir = parent_dir
  else
    let s:current_dir = parent_dir.s:PATH_SEPERATOR
  endif
  call s:set_prompt()
  call s:filter_or_send_message()
endfunction

function! s:filter_or_send_message() abort
  call g:clap.preview.hide()
  if has_key(s:filer_cache, s:current_dir)
    call s:do_filter()
  else
    call clap#client#call('filer', function('s:handle_result'), {'cwd': s:current_dir})
  endif
endfunction

function! s:bs_action() abort
  call clap#highlight#clear()

  let input = g:clap.input.get()
  if input ==# ''
    call s:goto_parent()
  else
    call g:clap.input.set(input[:-2])
    call s:filter_or_send_message()
  endif
  return ''
endfunction

function! s:do_filter() abort
  let query = g:clap.input.get()
  let candidates = s:filer_cache[s:current_dir]
  if query ==# ''
    call g:clap.display.set_lines(candidates)
    call g:clap#display_win.shrink_if_undersize()
  else
    call clap#filter#on_typed(function('clap#filter#sync'), query, candidates)
  endif
endfunction

function! s:reset_to(new_dir) abort
  let s:current_dir = a:new_dir
  call s:set_prompt()
  call clap#highlight#clear()
  call g:clap.input.set('')
  call s:filter_or_send_message()
endfunction

function! s:get_current_entry() abort
  let curline = g:clap.display.getcurline()
  if g:clap_enable_icon
    let curline = curline[4:]
  endif
  return s:smart_concatenate(s:current_dir, curline)
endfunction

function! s:try_go_to_dir_is_ok() abort
  let input = g:clap.input.get()
  if input[-1:] ==# s:PATH_SEPERATOR
    if isdirectory(expand(input))
      call s:reset_to(expand(input))
      return v:true
    endif
  endif
  return v:false
endfunction

function! s:tab_action() abort
  if s:try_go_to_dir_is_ok()
    return
  endif

  if exists('g:__clap_has_no_matches') && g:__clap_has_no_matches
    return
  endif

  if has_key(s:filer_error_cache, s:current_dir)
    call g:clap.display.set_lines([s:filer_error_cache[s:current_dir]])
    return
  endif

  if has_key(s:filer_empty_cache, s:current_dir)
    if g:clap.display.get_lines() != [s:DIRECTORY_IS_EMPTY]
      call g:clap.display.set_lines([s:DIRECTORY_IS_EMPTY])
    endif
    return
  endif

  let current_entry = s:get_current_entry()
  if filereadable(current_entry)
    call clap#preview#file(current_entry)
    return ''
  else
    call g:clap.preview.hide()
  endif

  call s:reset_to(current_entry)

  return ''
endfunction

function! s:smart_concatenate(cur_dir, curline) abort
  if a:cur_dir[-1:] ==# s:PATH_SEPERATOR
    return a:cur_dir.a:curline
  else
    return a:cur_dir.s:PATH_SEPERATOR.a:curline
  endif
endfunction

function! s:filer_sink(selected) abort
  let curline = g:clap_enable_icon ? a:selected[4:] : a:selected
  execute 'edit' s:smart_concatenate(s:current_dir, curline)
endfunction

function! s:filer_on_typed() abort
  " <Tab> and <Backspace> also trigger the CursorMoved event.
  " s:filter_or_send_message() is already handled in tab and bs action,
  " on_typed handler only needs to take care of the filtering.
  if exists('s:filer_cache') && has_key(s:filer_cache, s:current_dir)
    let cur_input = g:clap.input.get()
    if cur_input ==# s:last_input
      return
    endif
    let s:last_input = cur_input
    call clap#highlight#clear()
    call s:do_filter()
  endif
  return ''
endfunction

" Deprecated now.
function! s:sync_on_move_impl() abort
  let current_entry = s:get_current_entry()
  if filereadable(current_entry)
    call clap#preview#file(current_entry)
  else
    call g:clap.preview.hide()
  endif
endfunction

function! s:filer_handle_on_move_result(result) abort
  if empty(a:result.lines)
    call g:clap.preview.show(['Empty entries'])
  else
    call g:clap.preview.show(a:result.lines)
    if has_key(a:result, 'is_dir')
      call g:clap.preview.set_syntax('clap_filer')
      call clap#preview#clear_header_highlight()
    else
      if has_key(a:result, 'fname')
        call g:clap.preview.set_syntax(clap#ext#into_filetype(a:result.fname))
      endif
      call clap#preview#highlight_header()
    endif
  endif
endfunction

function! s:filer.on_move_async() abort
  call clap#client#call_on_move('filer/on_move', function('s:filer_handle_on_move_result'), {'cwd': s:current_dir})
endfunction

function! s:filer_on_no_matches(input) abort
  execute 'edit' a:input
endfunction

if has('win32')
  function! s:normalize_path_sep(path) abort
    return substitute(a:path, '[/\\]',s:PATH_SEPERATOR,'')
  endfunction
else
  function! s:normalize_path_sep(path) abort
    return a:path
  endfunction
endif

function! s:set_initial_current_dir() abort
  if empty(g:clap.provider.args)
    let s:current_dir = getcwd()
    if s:current_dir[-1:] !=# s:PATH_SEPERATOR
      let s:current_dir = s:current_dir.s:PATH_SEPERATOR
    endif
    return
  endif

  let maybe_dir = g:clap.provider.args[0]
  " %:p:h, % is actually g:clap.start.bufnr
  if maybe_dir =~# '^%.\+'
    let m = matchstr(maybe_dir, '^%\zs\(.*\)')
    let target_dir = fnamemodify(bufname(g:clap.start.bufnr), m)
  elseif isdirectory(expand(maybe_dir))
    let target_dir = maybe_dir
  else
    let s:current_dir = getcwd()
    if s:current_dir[-1:] !=# s:PATH_SEPERATOR
      let s:current_dir = s:current_dir.s:PATH_SEPERATOR
    endif
    return
  endif

  let target_dir = s:normalize_path_sep(expand(target_dir)) 
  if target_dir[-1:] ==# s:PATH_SEPERATOR
    let s:current_dir = target_dir 
  else
    let s:current_dir = target_dir.s:PATH_SEPERATOR
  endif
endfunction

function! s:start_rpc_service() abort
  let s:filer_cache = {}
  let s:filer_error_cache = {}
  let s:filer_empty_cache = {}
  let s:last_input = ''
  let s:winwidth = winwidth(g:clap.display.winid)
  call s:set_initial_current_dir()
  call s:set_prompt()
  call clap#client#call_on_init('filer/on_init', function('s:handle_result'), {'cwd': s:current_dir})
endfunction

let s:filer.init = function('s:start_rpc_service')
let s:filer.sink = function('s:filer_sink')
let s:filer.syntax = 'clap_filer'
let s:filer.on_typed = function('s:filer_on_typed')
let s:filer.bs_action = function('s:bs_action')
let s:filer.tab_action = function('s:tab_action')
let s:filer.source_type = g:__t_rpc
let s:filer.on_no_matches = function('s:filer_on_no_matches')
let g:clap#provider#filer# = s:filer

let &cpoptions = s:save_cpo
unlet s:save_cpo
