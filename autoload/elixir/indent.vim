if !exists("g:elixir_indent_max_lookbehind")
  let g:elixir_indent_max_lookbehind = 30
endif

" Return the effective value of 'shiftwidth'
function! s:sw()
  return &shiftwidth == 0 ? &tabstop : &shiftwidth
endfunction

" Logs a debug message. Messages can be viewed in `:messages`. Debug messages
" can be turned toggled by setting `g:elixir_indent_debug`:
"
"   " enable debug messages
"   let g:elixir_indent_debug = 1
"
" @param [String] str - the message to log
function! s:debug(str)
  if exists("g:elixir_indent_debug") && g:elixir_indent_debug
    echom a:str
  endif
endfunction

" DRY up regex for keywords that 1) makes sure we only look at complete words
" and 2) ignores atoms
function! s:keyword(expr)
  return ':\@<!\<\C\%('.a:expr.'\)\>:\@!'
endfunction

" This pattern defines the Elixir keywords that can start blocks. These all
" can be terminated by an `end` *AND* take `do: ...` form
let s:block_start_pattern = s:keyword('\<with\>\|\<if\>\|\<def\>\|\<defmodule\>\|\<defmacro\>\|\<defprotocol\>\|\<defimpl\>\|\<defmacrop\>\|\<defp\>\|\<case\>\|\<cond\>\|\<try\>\|\<receive\>')
let s:block_end_pattern = s:keyword('end')
let s:block_do_pattern = ':\@<!\<\Cdo\>'

let s:open_pattern = '\C\%({\|\[\|(\)'
let s:close_pattern = '\C\%(\]\|}\|)\)'

function! elixir#indent#indent(lnum)
  let lnum = a:lnum
  let text = getline(lnum)
  let prev_nb_lnum = prevnonblank(lnum-1)
  let prev_nb_text = getline(prev_nb_lnum)

  call s:debug("==> Indenting line " . lnum)
  call s:debug("text = '" . text . "'")

  let handlers = [
        \'top_of_file',
        \'starts_with_end',
        \'starts_with_mid_or_end_block_keyword',
        \'following_trailing_binary_operator',
        \'starts_with_pipe',
        \'starts_with_close_bracket',
        \'starts_with_binary_operator',
        \'inside_block_structure',
        \'inside_generic_block',
        \'follow_prev_nb'
        \]
  for handler in handlers
    call s:debug('testing handler elixir#indent#handle_'.handler)
    let indent = function('elixir#indent#handle_'.handler)(lnum, text, prev_nb_lnum, prev_nb_text)
    if indent != -1
      call s:debug('elixir#indent#handle_'.handler.' returned '.indent)
      return indent
    endif
  endfor

  call s:debug("defaulting")
  return 0
endfunction

" Converts a position to an indent value.
"
" @param [Integer] pos - a position
" @return [Integer] the corresponding indent
function! s:pos_to_indent(pos)
  return a:pos - 1
endfunction

" Converts a position to an indent value.
"
" @param [Integer] col - a column
" @return [Integer] the corresponding indent
function! s:col_to_indent(col)
  return a:col - 1
endfunction

" Returns 0 or 1 based on whether or not the text starts with the given
" expression and is not a string or comment
function! s:starts_with(text, expr, lnum)
  let pos = match(a:text, '^\s*'.a:expr)
  if pos == -1
    return 0
  else
    " NOTE: @jbodah 2017-02-24: pos is the index of the match which is
    " zero-indexed. Add one to make it the column number
    if s:is_string_or_comment(a:lnum, pos + 1)
      return 0
    else
      return 1
    end
  end
endfunction

" Returns 0 or 1 based on whether or not the text ends with the given
" expression and is not a string or comment
function! s:ends_with(text, expr, lnum)
  let pos = match(a:text, a:expr.'\s*$')
  if pos == -1
    return 0
  else
    if s:is_string_or_comment(a:lnum, pos)
      return 0
    else
      return 1
    end
  end
endfunction

" Returns 0 or 1 based on whether or not the given line number and column
" number pair is a string or comment
function! s:is_string_or_comment(line, col)
  return synIDattr(synID(a:line, a:col, 1), "name") =~ '\%(String\|Comment\)'
endfunction

" Skip expression for searchpair. Returns 0 or 1 based on whether the value
" under the cursor is a string or comment
function! elixir#indent#searchpair_back_skip()
  " NOTE: @jbodah 2017-02-27: for some reason this function gets called with
  " and index that doesn't exist in the line sometimes. Detect and account for
  " that situation
  let curr_col = col('.')
  if getline('.')[curr_col-1] == ''
    let curr_col = curr_col-1
  endif
  return s:is_string_or_comment(line('.'), curr_col)
endfunction

" Start at the end of text and search backwards looking for a match. Also peek
" ahead if we get a match to make sure we get a complete match. This means
" that the result should be the position of the start of the right-most match
function! s:find_last_pos(lnum, text, match)
  let last = len(a:text) - 1
  let c = last

  while c >= 0
    let substr = strpart(a:text, c, last)
    let peek = strpart(a:text, c - 1, last)
    let ss_match = match(substr, a:match)
    if ss_match != -1
      let peek_match = match(peek, a:match)
      if peek_match == ss_match + 1
        let syng = synIDattr(synID(a:lnum, c + ss_match, 1), 'name')
        if syng !~ '\%(String\|Comment\)'
          return c + ss_match
        end
      end
    end
    let c -= 1
  endwhile

  return -1
endfunction

" Indent handler that indents if we are at the top of the file.
" Returns -1 if the indent can't be handled by this function.
"
" @param [Integer] _lnum - unused
" @param [String] _text - unused
" @param [Integer] prev_nb_lnum - line number of the previous non-blank line
" @param [String] _prev_nb_text - unused
" @return [Integer] 0 if top of file, else -1
function! elixir#indent#handle_top_of_file(_lnum, _text, prev_nb_lnum, _prev_nb_text)
  if a:prev_nb_lnum == 0
    return 0
  else
    return -1
  end
endfunction

function! elixir#indent#handle_follow_prev_nb(_lnum, _text, prev_nb_lnum, prev_nb_text)
  return s:get_base_indent(a:prev_nb_lnum, a:prev_nb_text)
endfunction

" Given the line at `lnum`, returns the indent of the line that acts as the 'base indent'
" for this line. In particular it traverses backwards up things like pipelines
" to find the beginning of the expression
function! s:get_base_indent(lnum, text)
  let prev_nb_lnum = prevnonblank(a:lnum - 1)
  let prev_nb_text = getline(prev_nb_lnum)

  let binary_operator = '\%(=\|<>\|>>>\|<=\|||\|+\|\~\~\~\|-\|&&\|<<<\|/\|\^\^\^\|\*\)'
  let data_structure_close = '\%(\]\|}\|)\)'
  let pipe = '|>'

  if s:starts_with(a:text, binary_operator, a:lnum)
    return s:get_base_indent(prev_nb_lnum, prev_nb_text)
  elseif s:starts_with(a:text, pipe, a:lnum)
    return s:get_base_indent(prev_nb_lnum, prev_nb_text)
  elseif s:ends_with(prev_nb_text, binary_operator, prev_nb_lnum)
    return s:get_base_indent(prev_nb_lnum, prev_nb_text)
  elseif s:ends_with(a:text, data_structure_close, a:lnum)
    let data_structure_open = '\%(\[\|{\|(\)'
    let close_match_idx = match(a:text, data_structure_close . '\s*$')
    let _move = cursor(a:lnum, close_match_idx + 1)
    let [open_match_lnum, open_match_col] = searchpairpos(data_structure_open, '', data_structure_close, 'bnW')
    let open_match_text = getline(open_match_lnum)
    return s:get_base_indent(open_match_lnum, open_match_text)
  else
    return indent(a:lnum)
  endif
endfunction

" TODO: @jbodah 2017-03-31: remove
" function! elixir#indent#handle_following_trailing_do(lnum, text, prev_nb_lnum, prev_nb_text)
"   if s:ends_with(a:prev_nb_text, s:keyword('do'), a:prev_nb_lnum)
"     if s:starts_with(a:text, s:keyword('end'), a:lnum)
"       return indent(a:prev_nb_lnum)
"     else
"       return indent(a:prev_nb_lnum) + s:sw()
"     end
"   else
"     return -1
"   endif
" endfunction

function! elixir#indent#handle_following_trailing_binary_operator(lnum, text, prev_nb_lnum, prev_nb_text)
  let binary_operator = '\%(=\|<>\|>>>\|<=\|||\|+\|\~\~\~\|-\|&&\|<<<\|/\|\^\^\^\|\*\)'

  if s:ends_with(a:prev_nb_text, binary_operator, a:prev_nb_lnum)
    return indent(a:prev_nb_lnum) + s:sw()
  else
    return -1
  endif
endfunction

function! elixir#indent#handle_following_prev_end(_lnum, _text, prev_nb_lnum, prev_nb_text)
  if s:ends_with(a:prev_nb_text, s:block_end_pattern, a:prev_nb_lnum)
    return indent(a:prev_nb_lnum)
  else
    return -1
  endif
endfunction

function! elixir#indent#handle_starts_with_pipe(lnum, text, prev_nb_lnum, prev_nb_text)
  if s:starts_with(a:text, '|>', a:lnum)
    let match_operator = '\%(!\|=\|<\|>\)\@<!=\%(=\|>\|\~\)\@!'
    let pos = s:find_last_pos(a:prev_nb_lnum, a:prev_nb_text, match_operator)
    if pos == -1
      return indent(a:prev_nb_lnum)
    else
      let next_word_pos = match(strpart(a:prev_nb_text, pos+1, len(a:prev_nb_text)-1), '\S')
      if next_word_pos == -1
        return indent(a:prev_nb_lnum) + s:sw()
      else
        return pos + 1 + next_word_pos
      end
    end
  else
    return -1
  endif
endfunction

" function! elixir#indent#handle_starts_with_comment(_lnum, text, prev_nb_lnum, _prev_nb_text)
"   if match(a:text, '^\s*#') != -1
"     return indent(a:prev_nb_lnum)
"   else
"     return -1
"   endif
" endfunction

" Indent handler that indents the current line starts with an "end". In this
" case we want to match it with a "do" or "fn". Returns -1 if the indent
" can't be handled by this function. Else returns the indentation for the
" line.
"
" @param [Integer] lnum - unused
" @param [String] text - unused
" @param [Integer] prev_nb_lnum - line number of the previous non-blank line
" @param [String] _prev_nb_text - unused
" @return [Integer] -1 if can't be handled, else the indent value
function! elixir#indent#handle_starts_with_end(lnum, text, _prev_nb_lnum, _prev_nb_text)
  if s:starts_with(a:text, s:block_end_pattern, a:lnum)
    let skip_pattern = "line('.') == " . line('.') . " || elixir#indent#searchpair_back_skip()"
    let [pair_lnum, pair_pos] = searchpairpos(s:block_start_pattern, '', s:block_end_pattern.'\zs', 'bnW', skip_pattern)
    return pair_pos - 1
  else
    return -1
  endif
endfunction

function! elixir#indent#handle_starts_with_mid_or_end_block_keyword(lnum, text, _prev_nb_lnum, _prev_nb_text)
  if s:starts_with(a:text, s:keyword('catch\|rescue\|after\|else'), a:lnum)
    let pair_lnum = searchpair(s:keyword('with\|receive\|try\|if\|fn'), s:keyword('catch\|rescue\|after\|else').'\zs', s:block_end_pattern, 'bnW', "line('.') == " . line('.') . " || elixir#indent#searchpair_back_skip()")
    return indent(pair_lnum)
  else
    return -1
  endif
endfunction

function! elixir#indent#handle_starts_with_close_bracket(lnum, text, _prev_nb_lnum, _prev_nb_text)
  if s:starts_with(a:text, '\%(\]\|}\|)\)', a:lnum)
    let [pair_lnum, pair_col] = searchpairpos('\%(\[\|{\|(\)', '', '\%(\]\|}\|)\)', 'bnW', "line('.') == " . line('.') . " || elixir#indent#searchpair_back_skip()")
    let pair_text = getline(pair_lnum)
    return s:indent_of_final_expression_from_pos(pair_text, pair_col - 1)
  else
    return -1
  endif
endfunction

function! elixir#indent#handle_starts_with_binary_operator(lnum, text, prev_nb_lnum, prev_nb_text)
  let binary_operator = '\%(=\|<>\|>>>\|<=\|||\|+\|\~\~\~\|-\|&&\|<<<\|/\|\^\^\^\|\*\)'

  if s:starts_with(a:text, binary_operator, a:lnum)
    let match_operator = '\%(!\|=\|<\|>\)\@<!=\%(=\|>\|\~\)\@!'
    let pos = s:find_last_pos(a:prev_nb_lnum, a:prev_nb_text, match_operator)
    if pos == -1
      return indent(a:prev_nb_lnum)
    else
      let next_word_pos = match(strpart(a:prev_nb_text, pos+1, len(a:prev_nb_text)-1), '\S')
      if next_word_pos == -1
        return indent(a:prev_nb_lnum) + s:sw()
      else
        return pos + 1 + next_word_pos
      end
    end
  else
    return -1
  endif
endfunction

" Indent handler that indents based on the block structure that we're in.
" We define a block as one of the following:
"   * `with`
"   * `if`
"   * `case`
"   * `cond`
"   * `try`
"   * `receive`
"   * `fn`
"   * `def` or `defp`
"   * a map or tuple (i.e. `{`)
"   * a list (i.e. `[`)
"   * something in parens (i.e. `(`)
"
" In the case of nesting, the most relevant block is the one that is
" innermost, so we need to first detect which kind of block we are in. Blocks
" are handled differently (e.g. some perform pattern matching) so we need to
" handle each block type separately.
"
" @param [Integer] lnum - line number of the line to indent
" @param [String] text - text of the line to indent
" @param [Integer] prev_nb_lnum - line number of the previous non-blank line
" @param [String] prev_nb_text - text of the previous non-blank line
" @return [Integer] -1 if can't be handled, else the indent value
function! elixir#indent#handle_inside_block_structure(lnum, text, prev_nb_lnum, prev_nb_text)
  let search_opts = 'bnW'
  let skip_expression = "line('.') == " . line('.') . " || elixir#indent#searchpair_back_skip()"
  " let max_lookbehind = max([0, a:lnum - g:elixir_indent_max_lookbehind])

  let [innermost_block_head_lnum, innermost_block_head_pos] = searchpairpos(s:block_start_pattern, '', s:keyword('do'), search_opts, skip_expression)
  call s:debug("block_head: ".string([innermost_block_head_lnum, innermost_block_head_pos]))

  let [innermost_block_body_lnum, innermost_block_body_pos] = searchpairpos(s:keyword('do'), '', s:block_end_pattern, search_opts, skip_expression)
  call s:debug("block_body: ".string([innermost_block_body_lnum, innermost_block_body_pos]))

  let [innermost_data_structure_lnum, innermost_data_structure_pos] = searchpairpos(s:open_pattern, '', s:close_pattern, search_opts, skip_expression)
  call s:debug("data_structure: ".string([innermost_data_structure_lnum, innermost_data_structure_pos]))

  let [innermost_fn_lnum, innermost_fn_pos] = searchpairpos(s:keyword('fn'), '', s:keyword('end'), search_opts, skip_expression)
  call s:debug("fn: ".string([innermost_fn_lnum, innermost_fn_pos]))

  let pair_lnum = max([innermost_block_head_lnum, innermost_block_body_lnum, innermost_data_structure_lnum, innermost_fn_lnum])
  let competitors = []
  if pair_lnum == innermost_block_head_lnum
    let competitors += [innermost_block_head_pos]
  endif
  if pair_lnum == innermost_block_body_lnum
    let competitors += [innermost_block_body_pos]
  endif
  if pair_lnum == innermost_data_structure_lnum
    let competitors += [innermost_data_structure_pos]
  endif
  if pair_lnum == innermost_fn_lnum
    let competitors += [innermost_fn_pos]
  endif
  let pair_col = max(competitors)

  let [block_type, block_head_lnum, block_head_col] = s:classify_block(pair_lnum, pair_col, 'head')
  call s:debug("classified: ".block_type)
  return function('elixir#indent#handle_block_indent_'.block_type)(block_head_lnum, block_head_col, pair_lnum, pair_col, a:lnum, a:text, a:prev_nb_lnum, a:prev_nb_text)
endfunction

" Classifies the block by reading characters from it. It could be a block head
" (e.g. def...do), a block body (e.g. do...end), or a data structure
function! s:classify_block(pair_lnum, pair_col, suffix)
  if a:pair_lnum != 0 || a:pair_col != 0
    let pair_text = getline(a:pair_lnum)
    let pair_char = pair_text[a:pair_col - 1]
    if pair_char == 'f'
      return ['fn_'.a:suffix, a:pair_lnum, a:pair_col]
    elseif pair_char == '['
      return ['square_bracket', a:pair_lnum, a:pair_col]
    elseif pair_char == '{'
      return ['curly_brace', a:pair_lnum, a:pair_col]
    elseif pair_char == '('
      return ['paren', a:pair_lnum, a:pair_col]
    elseif pair_char == 'w'
      return ['with_'.a:suffix, a:pair_lnum, a:pair_col]
    elseif pair_char == 'd'
      if pair_text[a:pair_col] == 'e'
        return ['def_'.a:suffix, a:pair_lnum, a:pair_col]
      else
        let _move = cursor(a:pair_lnum, a:pair_col)
        let [head_lnum, head_col] = searchpairpos(s:block_start_pattern, '', s:keyword('do'), 'bnW')
        return s:classify_block(head_lnum, head_col, 'body')
      endif
    else
      return ['keyword_'.a:suffix, a:pair_lnum, a:pair_col]
    end
  else
    return -1
  end
endfunction


" Block indent handler. Indent based on the fact that we know we're in a `def`
" body
function! elixir#indent#handle_block_indent_def_body(_block_head_lnum, block_head_col, _pair_lnum, _pair_col, _lnum, _text, _prev_nb_lnum, _prev_nb_text)
  return s:col_to_indent(a:block_head_col) + s:sw()
endfunction

" Block indent handler. Indent based on some keyword block. These can contain
" pattern matches
function! elixir#indent#handle_block_indent_keyword_body(block_head_lnum, block_head_col, pair_lnum, _pair_col, _lnum, text, prev_nb_lnum, prev_nb_text)
  let keyword_pattern = '\C\%(\<case\>\|\<cond\>\|\<try\>\|\<receive\>\|\<after\>\|\<catch\>\|\<rescue\>\|\<else\>\)'
  if a:pair_lnum
    " last line is a "receive" or something
    if s:starts_with(a:prev_nb_text, keyword_pattern, a:prev_nb_lnum)
      call s:debug("prev nb line is keyword")
      return indent(a:prev_nb_lnum) + s:sw()
    else
      return s:do_handle_inside_pattern_match_block(a:pair_lnum, a:text, a:prev_nb_lnum, a:prev_nb_text)
    end
  else
    return -1
  endif
endfunction

" Block indent handler. Indent inside curly brace
function! elixir#indent#handle_block_indent_curly_brace(block_head_lnum, block_head_col, _pair_lnum, _pair_col, _lnum, _text, _prev_nb_lnum, _prev_nb_text)
  let block_head_text = getline(a:block_head_lnum)
  return s:indent_of_final_expression_from_pos(block_head_text, a:block_head_col) + s:sw()
endfunction

" Block indent handler. Indent inside parens
function! elixir#indent#handle_block_indent_paren(block_head_lnum, block_head_col, _pair_lnum, _pair_col, _lnum, _text, _prev_nb_lnum, _prev_nb_text)
  let block_head_text = getline(a:block_head_lnum)
  return s:indent_of_final_expression_from_pos(block_head_text, a:block_head_col) + s:sw()
endfunction

" Block structure indent handler. Returns the proper indentation given
" a `def` or `defp` is the most-significant thing to indent by. Returns -1
" if the indent can't be handled by this function. Else returns the
" indent for the line.
"
" @param [Integer] _pair_lnum - unused
" @param [Integer] pair_col - column of the `def` statement
" @param [Integer] _lnum - unused
" @param [String] _text - unused
" @param [Integer] _prev_nb_lnum - unused
" @param [String] _prev_nb_text - unused
" @return [Integer] -1 for failure, else value to indent by
function! s:do_handle_inside_def_or_defp(_pair_lnum, pair_col, _lnum, _text, _prev_nb_lnum, _prev_nb_text)
  return s:col_to_indent(a:pair_col) + s:sw()
endfunction

" Block structure indent handler. Returns the proper indentation given
" a the `do...end` of the block body is the most-significant thing to
" indent by. Returns -1 if the indent can't be handled by this function.
" Else returns the indent for the line.
"
" @param [Integer] pair_lnum - line number of the `do` statement
" @param [Integer] pair_col - column of the `do` statement
" @param [Integer] _lnum - unused
" @param [String] _text - unused
" @param [Integer] _prev_nb_lnum - unused
" @param [String] _prev_nb_text - unused
" @return [Integer] -1 for failure, else value to indent by
"
"
" " TODO: @jbodah 2017-10-21: pair text
function! s:do_handle_inside_block_body(pair_lnum, pair_col, pair_text)
  " Step 1: Move the cursor to the `do`
  let _move = cursor(a:pair_lnum, a:pair_col)

  " Step 2: Jump to the block head
  let [head_lnum, head_pos] = searchpairpos(s:block_start_pattern, '', s:block_do_pattern, 'bnW')

  " Step 3: Return the indent based on the block head
  if a:pair_text[a:pair_col + 1] == ':'
    return s:pos_to_indent(head_pos)
  else
    return s:pos_to_indent(head_pos) + s:sw()
  endif
endfunction

function! s:do_handle_inside_with(pair_lnum, pair_col, lnum, text, prev_nb_lnum, prev_nb_text)
  if a:pair_lnum == a:lnum
    " This is the `with` line or an inline `with`/`do`
    call s:debug("current line is `with`")
    return -1
  else
    " Determine if in with/do, do/else|end, or else/end
    let start_pattern = '\C\%(\<with\>\|\<else\>\|\<do\>\)'
    let end_pattern = '\C\%(\<end\>\)'
    let pair_info = searchpairpos(start_pattern, '', end_pattern, 'bnW', "line('.') == " . line('.') . " || elixir#indent#searchpair_back_skip()")
    let pair_lnum = pair_info[0]
    let pair_col = pair_info[1]

    let pair_text = getline(pair_lnum)
    let pair_char = pair_text[pair_col - 1]

    if s:starts_with(a:text, '\Cdo:', a:lnum)
      call s:debug("current line is do:")
      return pair_col - 1 + s:sw()
    elseif s:starts_with(a:text, '\Celse:', a:lnum)
      call s:debug("current line is else:")
      return pair_col - 1
    elseif s:starts_with(a:text, '\C\(\<do\>\|\<else\>\)', a:lnum)
      call s:debug("current line is do/else")
      return pair_col - 1
    elseif s:starts_with(pair_text, '\C\(do\|else\):', pair_lnum)
      call s:debug("inside do:/else:")
      return pair_col - 1 + s:sw()
    elseif pair_char == 'w'
      call s:debug("inside with/do")
      return pair_col + 4
    elseif pair_char == 'd'
      call s:debug("inside do/else|end")
      return pair_col - 1 + s:sw()
    else
      call s:debug("inside else/end")
      return s:do_handle_inside_pattern_match_block(pair_lnum, a:text, a:prev_nb_lnum, a:prev_nb_text)
    end
  end
endfunction

" function! s:do_handle_inside_keyword_block(pair_lnum, _pair_col, _lnum, text, prev_nb_lnum, prev_nb_text)
"   let keyword_pattern = '\C\%(\<case\>\|\<cond\>\|\<try\>\|\<receive\>\|\<after\>\|\<catch\>\|\<rescue\>\|\<else\>\)'
"   if a:pair_lnum
"     " last line is a "receive" or something
"     if s:starts_with(a:prev_nb_text, keyword_pattern, a:prev_nb_lnum)
"       call s:debug("prev nb line is keyword")
"       return indent(a:prev_nb_lnum) + s:sw()
"     else
"       return s:do_handle_inside_pattern_match_block(a:pair_lnum, a:text, a:prev_nb_lnum, a:prev_nb_text)
"     end
"   else
"     return -1
"   endif
" endfunction

" Implements indent for pattern-matching blocks (e.g. case, fn, with/else)
function! s:do_handle_inside_pattern_match_block(block_start_lnum, text, prev_nb_lnum, prev_nb_text)
  if a:text =~ '->'
    call s:debug("current line contains ->")
    return indent(a:block_start_lnum) + s:sw()
  elseif a:prev_nb_text =~ '->'
    call s:debug("prev nb line contains ->")
    return indent(a:prev_nb_lnum) + s:sw()
  else
    return indent(a:prev_nb_lnum)
  end
endfunction

function! s:do_handle_inside_fn(pair_lnum, _pair_col, lnum, text, prev_nb_lnum, prev_nb_text)
  if a:pair_lnum && a:pair_lnum != a:lnum
    return s:do_handle_inside_pattern_match_block(a:pair_lnum, a:text, a:prev_nb_lnum, a:prev_nb_text)
  else
    return -1
  endif
endfunction

function! s:do_handle_inside_square_brace(pair_lnum, pair_col, _lnum, _text, _prev_nb_lnum, _prev_nb_text)
  " If in list...
  if a:pair_lnum != 0 || a:pair_col != 0
    let pair_text = getline(a:pair_lnum)
    let substr = strpart(pair_text, a:pair_col, len(pair_text)-1)
    let indent_pos = match(substr, '\S')
    if indent_pos != -1
      return indent_pos + a:pair_col
    else
      return indent(a:pair_lnum) + s:sw()
    endif
  else
    return -1
  end
endfunction

" function! s:do_handle_inside_curly_brace(pair_lnum, _pair_col, _lnum, _text, _prev_nb_lnum, _prev_nb_text)
"   return indent(a:pair_lnum) + s:sw()
" endfunction

" Block structure indent handler. Returns the proper indentation given
" parentheses are the most-significant thing to indent by. Returns -1
" if the indent can't be handled by this function. Else returns the
" indent for the line.
"
" @param [Integer] pair_lnum - line number of the opening '('
" @param [Integer] pair_col - column index of the opening '('
" @param [Integer] _lnum - unused
" @param [String] _text - unused
" @param [Integer] prev_nb_lnum - line number of the previous non-blank line
" @param [String] prev_nb_text - text of the previous non-blank line
" @return [Integer] -1 for failure, else value to indent by
function! s:do_handle_inside_parens(pair_lnum, pair_col, _lnum, _text, prev_nb_lnum, prev_nb_text)
  if a:pair_lnum
    if s:ends_with(a:prev_nb_text, '(', a:prev_nb_lnum)
      return s:indent_of_final_expression(a:prev_nb_text) + s:sw()
      " return indent(a:prev_nb_lnum) + s:sw()
    elseif a:pair_lnum == a:prev_nb_lnum
      " Align indent (e.g. "def add(a,")
      let pos = s:find_last_pos(a:prev_nb_lnum, a:prev_nb_text, '[^(]\+,')
      if pos == -1
        return 0
      else
        return pos
      end
    else
      return indent(a:prev_nb_lnum)
    end
  else
    return -1
  endif
endfunction

function! elixir#indent#handle_inside_generic_block(lnum, _text, prev_nb_lnum, prev_nb_text)
  let pair_lnum = searchpair(s:keyword('do\|fn'), '', s:block_end_pattern, 'bW', "line('.') == ".a:lnum." || s:is_string_or_comment(line('.'), col('.'))", max([0, a:lnum - g:elixir_indent_max_lookbehind]))
  if pair_lnum
    " TODO: @jbodah 2017-03-29: this should probably be the case in *all*
    " blocks
    if s:ends_with(a:prev_nb_text, ',', a:prev_nb_lnum)
      return indent(pair_lnum) + 2 * s:sw()
    else
      return indent(pair_lnum) + s:sw()
    endif
  else
    return -1
  endif
endfunction

" Returns the indent of the final expression in the given `text`. Returns -1
" if the final expression runs on to a previous line.
"
" @param [String] text - the text to search in
" @return [Integer] -1 if failed to end the expression. Else the indent
function! s:indent_of_final_expression(text)
  let indent = len(a:text)
  let reversed_chars = reverse(split(a:text, '\zs'))
  for char in reversed_chars
    if char == ' '
      return indent
    else
      let indent -= 1
    endif
  endfor

  return -1
endfunction

" Returns the indent of the final expression in the given `text`. Returns -1
" if the final expression runs on to a previous line.
"
" @param [String] text - the text to search in
" @param [String] pos - the position to start the search in
" @return [Integer] -1 if failed to end the expression. Else the indent
function! s:indent_of_final_expression_from_pos(text, pos)
  let substr = strpart(a:text, 0, a:pos)
  call s:debug(substr)
  let indent = len(substr)
  let reversed_chars = reverse(split(substr, '\zs'))
  for char in reversed_chars
    if char == ' '
      return indent
    else
      let indent -= 1
    endif
  endfor

  return -1
endfunction

" TODO: @jbodah 2017-10-20: use  prev indent when following comma
"
" @impl true
" def datetime_to_string(
"       year,
"       month,
"       day,
"       hour,
"       minute,
"       second,
"       microsecond,
"       _time_zone,
"       zone_abbr,
"       _utc_offset,
"       _std_offset
"     ) do
"   "#{year}-#{month}-#{day}" <>
"     Calendar.ISO.time_to_string(hour, minute, second, microsecond) <> " #{zone_abbr} (HE)"
" end
