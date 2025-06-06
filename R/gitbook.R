#' The GitBook output format
#'
#' This output format function ported a style provided by GitBook
#' (\url{https://www.gitbook.com}) for R Markdown. To read more about this
#' format, see:
#' \url{https://bookdown.org/yihui/bookdown/html.html#gitbook-style}
#'
#' @inheritParams html_chapters
#' @param fig_caption,number_sections,self_contained,anchor_sections,lib_dir,pandoc_args,code_folding,extra_dependencies,...
#' Arguments to be passed to \code{rmarkdown::\link[rmarkdown]{html_document}()}
#' (\code{...} not including \code{toc}, and \code{theme}).
#' @param template Pandoc template to use for rendering. Pass \code{"default"}
#'   to use the bookdown default template; pass a path to use a custom template.
#'   The default template should be sufficient for most use cases. In case you
#'   want to develop a custom template, we highly recommend to start from the
#'   default template:
#'   \url{https://github.com/rstudio/bookdown/blob/master/inst/templates/gitbook.html}.
#' @param config A list of configuration options for the gitbook style, such as
#'   the font/theme settings.
#' @param table_css \code{TRUE} to load gitbook's default CSS for tables. Choose
#'   \code{FALSE} to unload and use customized CSS (for example, bootstrap) via
#'   the \code{css} option. Default is \code{TRUE}.
#' @export
gitbook = function(
  fig_caption = TRUE, number_sections = TRUE, self_contained = FALSE,
  anchor_sections = TRUE, lib_dir = 'libs', global_numbering = !number_sections,
  pandoc_args = NULL, extra_dependencies = list(), ..., template = 'default',
  split_by = c('chapter', 'section', '0', '1', '2', '3', '4', '5', '6', 'chapter+number',
               'section+number', '0+number', '1+number', '2+number', '3+number',
               '4+number', '5+number', '6+number', 'rmd', 'none') ,
  split_bib = TRUE, config = list(), table_css = TRUE, code_folding = c("none", "show", "hide")
) {
  gb_config = config
  html_document2 = function(..., extra_dependencies = list()) {
    rmarkdown::html_document(
      ..., extra_dependencies = c(gitbook_dependency(table_css, gb_config), extra_dependencies)
    )
  }
  if (identical(template, 'default')) {
    template = bookdown_file('templates', 'gitbook.html')
  }
  lua_filters = c()
  code_folding = match.arg(code_folding)
  if (code_folding != "none") {
    extra_dependencies = append(extra_dependencies,
                                 list(rmarkdown::html_dependency_codefolding_lua()))
    pandoc_args = c(pandoc_args,
                     rmarkdown::pandoc_metadata_arg("rmd_codefolding_lua", code_folding))
    lua_filters = c(lua_filters, rmarkdown::pkg_file_lua("codefolding.lua"))
  }
  config = html_document2(
    toc = TRUE, number_sections = number_sections, fig_caption = fig_caption,
    self_contained = self_contained, anchor_sections = anchor_sections,
    lib_dir = lib_dir, theme = NULL, extra_dependencies = extra_dependencies,
    template = template, pandoc_args = pandoc_args2(pandoc_args), ...
  )
  config$pandoc$lua_filters = append(config$pandoc$lua_filters, lua_filters)
  split_by = as.character(split_by)
  split_by = match.arg(split_by)
  post = config$post_processor  # in case a post processor have been defined
  config$post_processor = function(metadata, input, output, clean, verbose) {
    if (is.function(post)) output = post(metadata, input, output, clean, verbose)
    on.exit(write_search_data(), add = TRUE)

    # a hack to remove Pandoc's margin for code blocks since gitbook has already
    # defined margin on <pre> (there would be too much bottom margin)
    x = read_utf8(output)
    x = x[x != 'div.sourceCode { margin: 1em 0; }']
    write_utf8(x, output)

    move_files_html(output, lib_dir)
    output2 = split_chapters(
      output, gitbook_page, global_numbering, split_by, split_bib, gb_config, split_by
    )
    if (file.exists(output) && !same_path(output, output2)) file.remove(output)
    move_files_html(output2, lib_dir)
    output2
  }
  config = common_format_config(config, 'html')
  config
}

gitbook_search = local({
  data = NULL
  list(
    get = function() data,
    collect = function(...) data <<- c(data, ...),
    empty = function() data <<- NULL
  )
})

write_search_data = function() {
  x = gitbook_search$get()
  if (length(x) == 0) return()
  gitbook_search$empty()
  x = matrix(strip_search_text(x), nrow = 3)
  x = apply(x, 2, xfun::json_vector, to_array = TRUE)
  x = paste0('[\n', paste0(x, collapse = ',\n'), '\n]')
  x = gsub('[^[:print:]]', '', x)
  write_utf8(x, output_path('search_index.json'))
}

gitbook_dependency = function(table_css, config = list()) {
  assets = bookdown_file('resources', 'gitbook')
  owd = setwd(assets); on.exit(setwd(owd), add = TRUE)
  app = if (file.exists('js/app.min.js')) 'app.min.js' else 'app.js'
  # TODO: download and a local copy of fuse.js?
  fuse = htmltools::htmlDependency(
    'fuse', '6.4.6', c(href = 'https://cdn.jsdelivr.net/npm/fuse.js@6.4.6'),
    script = 'dist/fuse.min.js'
  )
  if (is.logical(config$search)) {
    lunr = FALSE
    if (!config$search) fuse = NULL
  } else {
    # use fuse as the search engine by default
    lunr = identical(config$search$engine, 'lunr')
  }
  list(jquery_dependency(), fuse, htmltools::htmlDependency(
    'gitbook', '2.6.7', src = assets,
    stylesheet = file.path('css', c(
      'style.css', if (table_css) 'plugin-table.css', 'plugin-bookdown.css',
      'plugin-highlight.css', 'plugin-search.css', 'plugin-fontsettings.css',
      'plugin-clipboard.css'
    )),
    script = file.path('js', c(
      app, if (lunr) 'lunr.js', 'clipboard.min.js', 'plugin-search.js', 'plugin-sharing.js',
      'plugin-fontsettings.js', 'plugin-bookdown.js', 'jquery.highlight.js',
      'plugin-clipboard.js'
    ))
  ))
}

gitbook_page = function(
  head, toc, chapter, link_prev, link_next, rmd_cur, html_cur, foot,
  config, split_by
) {
  toc = gitbook_toc(toc, rmd_cur, config[['toc']])

  has_prev = length(link_prev) > 0
  has_next = length(link_next) > 0
  a_prev = if (has_prev) sprintf(
    '<a href="%s" class="navigation navigation-prev %s" aria-label="Previous page"><i class="fa fa-angle-left"></i></a>',
    link_prev, if (has_next) '' else 'navigation-unique'
  ) else ''
  a_next = if (has_next) sprintf(
    '<a href="%s" class="navigation navigation-next %s" aria-label="Next page"><i class="fa fa-angle-right"></i></a>',
    link_next, if (has_prev) '' else 'navigation-unique'
  ) else ''
  foot = sub('<!--bookdown:link_prev-->', a_prev, foot)
  foot = sub('<!--bookdown:link_next-->', a_next, foot)

  l_prev = if (has_prev) sprintf('<link rel="prev" href="%s"/>', link_prev) else ''
  l_next = if (has_next) sprintf('<link rel="next" href="%s"/>', link_next) else ''
  head = sub('<!--bookdown:link_prev-->', l_prev, head)
  head = sub('<!--bookdown:link_next-->', l_next, head)
  head = sub('#bookdown:version#', packageVersion('bookdown'), head)

  # gitbook JS scripts only work after the DOM has been loaded, so move them
  # from head to foot
  i = grep('^\\s*<script src=".+/gitbook([^/]+)?/js/[.a-z-]+[.]js"></script>\\s*$', head)
  # it is probably a self-contained page, so look for script node.
  # from pandoc2, they are not always base64 encoded scripts, so start and end of scripts
  # node must be found and moved.
  if (length(i) == 0) {
    s_start = grep(
      '^\\s*<script( src="data:application/(x-)?javascript;base64,[^"]+")?>', head
    )
    s_end = grep("</script>\\s*$", head)
    # find all lines to move
    i = unlist(mapply(seq.int, s_start, s_end, SIMPLIFY = FALSE))
  }
  s = head[i]; head[i] = ''
  j = grep('<!--bookdown:config-->', foot)[1]
  foot[j] = paste(c(s, foot[j]), collapse = '\n')

  titles = paste(grep('^<(h[12])(>| ).+</\\1>.*$', chapter, value = TRUE), collapse = ' ')
  # when not rendering via render_book()  (but e.g. rmarkdown::render()), do not
  # collect search data because the output will be a single page: Ctrl + F!
  if (is.null(opts$get('book_filename'))) {
    config$search = FALSE
  } else {
    gitbook_search$collect(html_cur, titles, paste(chapter, collapse = ' '))
  }

  # you can set the edit setting in either _bookdown.yml or _output.yml
  for (type in c('edit', 'history', 'view')) {
    if (is.list(setting <- source_link_setting(config[[type]], type = type)))
      config[[type]] = setting
    if (length(rmd_cur) && is.list(config[[type]]))
      config[[type]][["link"]] = sprintf(config[[type]]$link, rmd_cur)
  }

  config$download = download_filenames(config)

  foot = sub('<!--bookdown:config-->', gitbook_config(config), foot)

  c(head, toc, chapter, foot)
}

gitbook_toc = function(x, cur, config) {
  i1 = find_token(x, '<!--bookdown:toc2:start-->')
  i2 = find_token(x, '<!--bookdown:toc2:end-->')
  x[i1] = ''; x[i2] = ''
  if (i2 - i1 < 2) return(x)
  toc = x[(i1 + 1):(i2 - 1)]

  # Remove possible empty span due to anchor section
  toc = gsub("<span></span>(?=</[ab]>)", "", toc, perl = TRUE)

  # numbered sections
  r = '^<li><a href="([^#]*)(#[^"]+)"[^>]*><span class="toc-section-number">([.A-Z0-9]+)</span>(.+)(</a>.*)$'
  i = grep(r, toc)
  toc[i] = gsub(
    r,
    '<li class="chapter" data-level="\\3" data-path="\\1"><a href="\\1\\2"><i class="fa fa-check"></i><b>\\3</b>\\4\\5',
    toc[i]
  )
  toc[i] = sub(' data-path="">', paste0(' data-path="', with_ext(cur, '.html'), '">'), toc[i])

  # unnumbered sections
  r = '^<li><a href="([^#]*)(#[^"]+)"[^>]*>((.+)</a>.*)$'
  i = grep(r, toc)
  toc[i] = gsub(
    r,
    '<li class="chapter" data-level="" data-path="\\1"><a href="\\1\\2"><i class="fa fa-check"></i>\\3',
    toc[i]
  )

  # remove the hash from the first TOC item if it has following items that share
  # the same base pathname, e.g. [index.html#foo, index.html#bar] ->
  # [index.html, index.html#bar]
  r = '^(<li class="chapter" data-level="[.A-Z0-9]*" data-path="[^"]+"><a href=")([^#]+)(#[^"]+)(">.+)$'
  i = grep(r, toc)
  i = i[!duplicated(gsub(r, '\\2', toc[i]))]
  toc[i] = gsub(r, '\\1\\2\\4', toc[i])

  # collapse sections under chapters
  if (isTRUE(config[['collapse']])) {
    r = '^<li .+ data-level="([^.]+)?" .+>.+</a><ul>$'
    i = grep(r, toc)
    toc[i] = gsub('<ul>$', '<ul style="display:none;">', toc[i])
  }

  if (toc[1] == '<ul>') {
    toc[1] = '<ul class="summary">'
    if (!is.null(extra <- config[['before']])) {
      toc[1] = paste(c(toc[1], extra, '<li class="divider"></li>'), collapse = '\n')
    }
  }
  n = length(toc)
  if (toc[n] == '</ul>') {
    if (!is.null(extra <- config[['after']])) {
      toc[n] = paste(c('<li class="divider"></li>', extra, toc[n]), collapse = '\n')
    }
  }
  x[(i1 + 1):(i2 - 1)] = toc
  x
}

gitbook_config = function(config = list()) {
  default = list(
    sharing = list(
      github = FALSE, facebook = TRUE, twitter = TRUE,
      linkedin = FALSE, weibo = FALSE, instapaper = FALSE, vk = FALSE,
      whatsapp = FALSE,
      all = c('facebook', 'twitter', 'linkedin', 'weibo', 'instapaper')
    ),
    fontsettings = list(theme = 'white', family = 'sans', size = 2),
    edit = list(link = NULL, text = NULL),
    history = list(link = NULL, text = NULL),
    view = list(link = NULL, text = NULL),
    download = NULL,
    # toolbar = list(position = 'static'),
    search = list(engine = 'fuse', options = NULL),
    toc = list(collapse = 'subsection')
  )
  if (isTRUE(config$search)) config$search = NULL
  if (isFALSE(config$search)) default$search = FALSE
  config = utils::modifyList(default, config, keep.null = TRUE)
  # remove these TOC config items since we don't need them in JavaScript
  config$toc$before = NULL; config$toc$after = NULL
  config = sprintf('gitbook.start(%s);', xfun::tojson(config))
  paste(
    '<script>', 'gitbook.require(["gitbook"], function(gitbook) {', config, '});',
    '</script>', sep = '\n'
  )
}

# infer pdf/epub/mobi filenames from the book filename
download_filenames = function(config) {
  if (length(exts <- load_config()[['download']]) == 0) exts = config$download
  if (identical(exts, FALSE)) return()
  if (is.list(exts)) return(exts)  # I assume you are doing it correctly
  if ((n <- length(grep('[.]', exts))) > 0) {
    if (length(exts) != n) stop(
      'You must provide either pure file extensions or full filenames'
    )
    return(exts)
  }
  # no downloads if not rendering with render_book() but render()
  if (is.null(book_name <- opts$get('book_filename'))) return()
  if (isTRUE(exts) || length(exts) == 0) {
    exts = c('pdf', 'epub', 'mobi')
    downloads = with_ext(book_name, exts)
    in_dir(output_path('.'), {
      downloads = downloads[file.exists(downloads)]
    })
  } else {
    downloads = with_ext(book_name, exts)
    i = match('rmd', exts)
    if (!is.na(i)) {
      r = '^(https://github.com/[^/]+/[^/]+)/edit/'
      if (is.character(link <- config$edit$link) && grepl(r, link)) {
        downloads[i] = gsub(r, '\\1/raw/', link)
      } else {
        warning('The edit link was not specified, and the download link for RMD will not work')
        downloads = downloads[-i]
      }
    }
  }
  if (length(downloads)) I(downloads)
}
