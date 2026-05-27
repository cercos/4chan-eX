Settings =
  init: ->
    # 4chan-eX settings link
    link = $.el 'a',
      className:   'settings-link fa fa-wrench'
      textContent: 'Settings'
      title:       '<%= meta.name %> Settings'
      href:        'javascript:;'
    $.on link, 'click', Settings.open

    Header.addShortcut 'settings', link, 820

    add = @addSection

    add 'General',  @general
    add 'Reading',  @reading
    add 'Media',    @media
    add 'Posting',  @posting
    add 'Styling',  @styling
    add 'Filters',  @filters
    add 'Sauce',    @sauce
    add 'Advanced', @advanced
    add 'Keybinds', @keybinds

    $.on d, 'AddSettingsSection',   Settings.addSection
    $.on d, 'OpenSettings', (e) -> Settings.open e.detail

    if g.SITE.software is 'yotsuba' and Conf['Disable Native Extension']
      if $.hasStorage
        # Run in page context to handle case where 4chan-eX has localStorage access but not the page.
        # (e.g. Pale Moon 26.2.2, GM 3.8, cookies disabled for 4chan only)
        $.global ->
          try
            settings = JSON.parse(localStorage.getItem '4chan-settings') or {}
            return if settings.disableAll
            settings.disableAll = true
            localStorage.setItem '4chan-settings', JSON.stringify settings
          catch
            Object.defineProperty window, 'Config', {value: {disableAll: true}}
      else
        $.global ->
          Object.defineProperty window, 'Config', {value: {disableAll: true}}

  open: (openSection) ->
    return if Settings.dialog
    $.event 'CloseMenu'

    Settings.dialog = dialog = $.el 'div',
      id:        'overlay'
    ,
      `<%= readHTML('Settings.html') %>`

    $.on $('.export', dialog), 'click',  Settings.export
    $.on $('.import', dialog), 'click',  Settings.import
    $.on $('.reset',  dialog), 'click',  Settings.reset
    $.on $('input[type=file]', dialog), 'change', Settings.onImport
    $.on $('.settings-search input', dialog), 'input', Settings.onSearchInput

    links = []
    container = $('.section-container', dialog)
    for section in Settings.sections
      section.el = $.el 'section',
        className: "section-#{section.hyphenatedTitle}"
        hidden: true
      $.add section.el, $.el 'h2',
        className: 'settings-section-header'
        textContent: section.title
      $.add container, section.el

      link = $.el 'a',
        className: "tab-#{section.hyphenatedTitle}"
        textContent: section.title
        href: 'javascript:;'
      $.on link, 'click', Settings.openSection.bind section
      links.push link
      if (
        section.title is openSection or
        (openSection is 'Main' and section.title is 'General') or
        (openSection is 'Filter' and section.title is 'Filters') or
        (openSection is 'Simple Filters' and section.title is 'Filters')
      )
        sectionToOpen = link
    $.add $('.sections-list', dialog), links
    (if sectionToOpen then sectionToOpen else links[0]).click() unless openSection is 'none'

    $.on $('.close', dialog), 'click', Settings.close
    $.on window, 'beforeunload', Settings.close
    $.on dialog, 'mousedown', (e) -> Settings.overlayMousedownTarget = e.target
    $.on dialog, 'click', Settings.overlayClick
    $.on dialog.firstElementChild, 'click', (e) -> e.stopPropagation()
    $.on d, 'keydown', Settings.keydown
    Settings.setupWindow dialog

    $.add d.body, dialog

    $.event 'OpenSettings', null, dialog

  openFilters: ->
    preferredMode = Conf['Open Filters Mode']
    if preferredMode in ['simple', 'advanced', 'filtered']
      Settings.forcedFiltersMode = preferredMode
    else
      delete Settings.forcedFiltersMode

    if Settings.dialog
      $('.tab-filters', Settings.dialog)?.click()
    else
      Settings.open 'Filters'

  close: ->
    return unless Settings.dialog
    # Unfocus current field to trigger change event.
    d.activeElement?.blur()
    Settings.saveWindowState()
    Settings.resizeObserver?.disconnect()
    delete Settings.resizeObserver
    Settings.clearDragHandle()
    $.off d, 'keydown', Settings.keydown
    Settings.dragEnd()
    $.rm Settings.dialog
    for section in Settings.sections
      delete section.el
      section.rendered = false
    delete Settings.dialog
    delete Settings.searchQuery
    delete Settings.filtersPreviewState
    delete Settings.forcedFiltersMode
    delete Settings.overlayMousedownTarget

  keydown: (e) ->
    return unless e.keyCode is 27
    Settings.close()

  onSearchInput: ->
    Settings.searchQuery = @value.toLowerCase().trim()
    Settings.applySearch()

  overlayClick: (e) ->
    return unless e.target is @
    return unless Settings.overlayMousedownTarget is @
    Settings.close()

  setupWindow: (dialog) ->
    win = dialog.firstElementChild
    win.classList.add 'settings-resizable'
    Settings.applyLayoutMode win
    Settings.applyWindowState win, Settings.windowState or Conf['settings.window']
    $.get 'settings.window', null, (state) ->
      return unless Settings.dialog and win is Settings.dialog.firstElementChild
      if state
        Settings.windowState = state
        Settings.applyWindowState win, state
    Settings.watchSize win
    Settings.setDragHandle win

  applyLayoutMode: (win) ->
    win.classList.remove 'settings-layout-classic'

  setDragHandle: (win) ->
    Settings.clearDragHandle()
    dialog = Settings.dialog
    dialog?.classList.remove 'settings-freeform'
    win.classList.remove 'settings-draggable'
    dialog?.classList.add 'settings-freeform'
    win.classList.add 'settings-draggable'
    dragHandle = $('.settings-titlebar', win)
    if dragHandle
      Settings.dragHandle = dragHandle
      $.on dragHandle, 'mousedown', Settings.dragStart

  clearDragHandle: ->
    return unless Settings.dragHandle
    $.off Settings.dragHandle, 'mousedown', Settings.dragStart
    delete Settings.dragHandle

  applyWindowState: (win, state) ->
    return unless state
    win.style.width = state.width if state.width
    win.style.height = state.height if state.height
    if state.left and state.top
      win.style.position = 'fixed'
      win.style.margin = '0'
      win.style.left = state.left
      win.style.top = state.top
      win.style.right = ''
      win.style.bottom = ''
    else
      win.style.position = ''
      win.style.margin = ''
      win.style.left = ''
      win.style.top = ''
      win.style.right = ''
      win.style.bottom = ''

  watchSize: (win) ->
    if window.ResizeObserver
      Settings.resizeObserver = new window.ResizeObserver ->
        Settings.queueSaveWindowState()
      Settings.resizeObserver.observe win

  queueSaveWindowState: ->
    clearTimeout Settings.sizeTimer if Settings.sizeTimer
    Settings.sizeTimer = setTimeout(Settings.saveWindowState, 250)

  saveWindowState: ->
    clearTimeout Settings.sizeTimer if Settings.sizeTimer
    delete Settings.sizeTimer
    win = Settings.dialog?.firstElementChild
    return unless win
    rect = win.getBoundingClientRect()
    state =
      width: "#{Math.round(rect.width)}px"
      height: "#{Math.round(rect.height)}px"
    if win.style.position is 'fixed'
      state.left = "#{Math.round(rect.left)}px"
      state.top = "#{Math.round(rect.top)}px"
    Settings.windowState = state
    $.set 'settings.window', state

  dragStart: (e) ->
    return if e.button isnt 0
    return if e.target.closest?('a, input, button, textarea, select')
    win = Settings.dialog?.firstElementChild
    return unless win
    e.preventDefault()
    rect = win.getBoundingClientRect()
    win.style.position = 'fixed'
    win.style.margin = '0'
    win.style.left = "#{rect.left}px"
    win.style.top = "#{rect.top}px"
    Settings.drag =
      win: win
      dx: e.clientX - rect.left
      dy: e.clientY - rect.top
    $.on d, 'mousemove', Settings.dragMove
    $.on d, 'mouseup', Settings.dragEnd

  dragMove: (e) ->
    return unless Settings.drag
    {win, dx, dy} = Settings.drag
    left = e.clientX - dx
    top = e.clientY - dy
    maxLeft = doc.clientWidth - 40
    maxTop = doc.clientHeight - 40
    left = Math.max 0, Math.min(left, maxLeft)
    top = Math.max 0, Math.min(top, maxTop)
    win.style.left = "#{left}px"
    win.style.top = "#{top}px"

  dragEnd: ->
    return unless Settings.drag
    $.off d, 'mousemove', Settings.dragMove
    $.off d, 'mouseup', Settings.dragEnd
    Settings.saveWindowState()
    delete Settings.drag

  sections: []

  addSection: (title, open) ->
    if typeof title isnt 'string'
      {title, open} = title.detail
    hyphenatedTitle = title.toLowerCase().replace /\s+/g, '-'
    Settings.sections.push {title, hyphenatedTitle, open, rendered: false}

  openSection: ->
    if selected = $ '.tab-selected', Settings.dialog
      $.rmClass selected, 'tab-selected'
    $.addClass $(".tab-#{@hyphenatedTitle}", Settings.dialog), 'tab-selected'
    for section in Settings.sections
      section.el.hidden = section isnt @
    unless @rendered
      @open @el, g
      @rendered = true
      Settings.restoreSectionHeader @
    @el.scrollTop = 0
    Settings.applySearch()
    $.event 'OpenSettings', null, @el

  restoreSectionHeader: (sectionObj) ->
    el = sectionObj.el
    return if $ '.settings-section-header', el
    h2 = $.el 'h2',
      className: 'settings-section-header'
      textContent: sectionObj.title
    el.insertBefore h2, el.firstChild

  applySearch: ->
    return unless Settings.dialog
    query = Settings.searchQuery or ''

    win = Settings.dialog.firstElementChild
    win.classList.toggle 'settings-searching', !!query

    activeSection = null
    if selectedTab = $ '.tab-selected', Settings.dialog
      for s in Settings.sections
        if selectedTab.classList.contains "tab-#{s.hyphenatedTitle}"
          activeSection = s
          break

    for sectionObj in Settings.sections
      section = sectionObj.el
      continue unless section

      if query and not sectionObj.rendered
        sectionObj.open section, g
        sectionObj.rendered = true
        Settings.restoreSectionHeader sectionObj

      for el in $$ '.settings-search-hidden', section
        $.rmClass el, 'settings-search-hidden'

      # Highlight matching text in the whole section (except previews)
      Settings.highlightSettingRow section, query

      if query
        # Hide all elements initially
        for el in $$ 'div[data-name], tr[data-name], .generated-highlight-group, .generated-highlight-auto-group, .generated-highlight-auto-row, fieldset, .settings-group-heading, table, thead, tbody, legend, h4', section
          $.addClass el, 'settings-search-hidden'

        hasMatch = false

        # 1. Search Standard Setting Rows (divs or table rows)
        for row in $$ 'div[data-name], tr[data-name]', section
          haystack = "#{row.dataset.name or ''} #{row.dataset.settingTitle} #{row.dataset.settingDescription or ''} #{row.dataset.searchKeywords or ''}".toLowerCase()
          if haystack.indexOf(query) >= 0
            hasMatch = true
            node = row
            while node and node isnt section
              node.classList.remove 'settings-search-hidden'
              node = node.parentElement
            child.classList.remove 'settings-search-hidden' for child in $$ '.settings-search-hidden', row

        # 2. Search Styling Groups and headings (except previews)
        for el in $$ '.generated-highlight-group, .generated-highlight-auto-group, legend, th, h4, .generated-highlight-help', section
          continue if el.closest('.generated-highlight-preview') or el.closest('.custom-css-editor')
          if el.textContent.toLowerCase().indexOf(query) >= 0
            hasMatch = true
            node = el
            while node and node isnt section
              node.classList.remove 'settings-search-hidden'
              node = node.parentElement
            child.classList.remove 'settings-search-hidden' for child in $$ '.settings-search-hidden', el

        # 3. Search Headings
        for heading in $$ '.settings-group-heading', section
          hit = heading.textContent.toLowerCase().indexOf(query) >= 0
          if hit
            hasMatch = true
            heading.classList.remove 'settings-search-hidden'
            # Also show everything in this group until the next heading
            node = heading.nextElementSibling
            while node and not node.classList.contains('settings-group-heading')
              node.classList.remove 'settings-search-hidden'
              child.classList.remove 'settings-search-hidden' for child in $$ '.settings-search-hidden', node
              node = node.nextElementSibling

        # 4. Search Fieldsets (except previews)
        for fs in $$ 'fieldset', section
          isPreview = fs.classList.contains('generated-highlight-preview') or fs.classList.contains('custom-css-editor')
          if not isPreview
            matchTarget = $('legend', fs)?.textContent or fs.textContent
            hit = matchTarget.toLowerCase().indexOf(query) >= 0
            if hit
              hasMatch = true
              fs.classList.remove 'settings-search-hidden'
              child.classList.remove 'settings-search-hidden' for child in $$ '.settings-search-hidden', fs

        section.hidden = not hasMatch
      else
        section.hidden = sectionObj isnt activeSection

  highlightSettingRow: (row, query) ->
    # Highlight matching text in labels, legends, descriptions, and table headers
    for el in $$ '.setting-title, .setting-description, legend, th, h4, .generated-highlight-help', row
      # Skip highlighting inside previews
      continue if el.closest('.generated-highlight-preview') or el.closest('.custom-css-editor')
      
      raw = el.dataset.rawText
      unless raw?
        raw = el.textContent
        el.dataset.rawText = raw
      if query
        rx = RegExp("(#{Settings.escapeRegExp(query)})", 'ig')
        el.innerHTML = raw.replace rx, '<mark>$1</mark>'
      else
        el.textContent = raw

  escapeRegExp: (s) ->
    s.replace /[.*+?^${}()|[\]\\]/g, '\\$&'

  warnings:
    localStorage: (cb) ->
      if $.cantSync
        why = if $.cantSet then 'save your settings' else 'synchronize settings between tabs'
        cb $.el 'li',
          textContent: """
            <%= meta.name %> needs local storage to #{why}.
            Enable it on boards.#{location.hostname.split('.')[1]}.org in your browser's privacy settings (may be listed as part of "local data" or "cookies").
          """
    ads: (cb) ->
      $.onExists doc, '.adg-rects > .desktop', (ad) -> $.onExists ad, 'iframe', ->
        url = Redirect.to 'thread', {boardID: 'qa', threadID: 362590}
        cb $.el 'li',
          `<%= html(
            'To protect yourself from <a href="${url}" target="_blank">malicious ads</a>,' +
            ' you should <a href="https://github.com/gorhill/uBlock#ublock-origin" target="_blank">block ads</a> on 4chan.'
          ) %>`

  stylingOptionNames: [
    'Time Formatting'
    'Relative Post Dates'
    'Relative Date Title'
    'File Info Formatting'
    'Custom Board Titles'
    'Persistent Custom Board Titles'
    'Color User IDs'
    'Count Posts by ID'
    'Remove Spoilers'
    'Reveal Spoilers'
    'Highlight Posts Quoting You'
    'Highlight Own Posts'
  ]

  searchKeywords:
    'Replace Thumbnails': 'replace gif jpg jpeg png webm mp4 ogv thumbnails original media'
    'Detailed Thread Stats': 'ip count page count purge position'

  getMainSettingLookup: ->
    lookup = $.dict()
    for keyFS, obj of Config.main
      for key, arr of obj when arr instanceof Array
        lookup[key] = arr
    lookup

  renderMainGroups: (section, options) ->
    {
      categories
      includeWarnings
      includeJSONIndex
      includeHiddenCount
      hideLegendFor
    } = options
    hideLegendFor ?= []

    if includeWarnings
      warnings = $.el 'fieldset',
        hidden: true
      ,
        `<%= html('<legend>Warnings</legend><ul></ul>') %>`
      addWarning = (item) ->
        $.add $('ul', warnings), item
        warnings.hidden = false
      for key, warning of Settings.warnings
        warning addWarning
      $.add section, warnings

    items  = $.dict()
    inputs = $.dict()
    addCheckboxes = (root, obj, includeSetting = -> true) ->
      containers = [root]
      count = 0
      for key, arr of obj when arr instanceof Array
        continue unless includeSetting key
        description = arr[1] or ''
        div = $.el 'div',
          `<%= html('<label><input type="checkbox" name="${key}"><span class="setting-title">${key}</span></label><span class="description">: <span class="setting-description">${description}</span></span>') %>`
        div.dataset.name = key
        div.dataset.settingTitle = key
        div.dataset.settingDescription = description
        if keywords = Settings.searchKeywords[key]
          div.dataset.searchKeywords = keywords
        input = $ 'input', div
        $.on input, 'change', $.cb.checked
        $.on input, 'change', -> @parentNode.parentNode.dataset.checked = @checked
        items[key]  = Conf[key]
        inputs[key] = input
        level = arr[2] or 0
        if containers.length <= level
          container = $.el 'div', className: 'suboption-list'
          $.add containers[containers.length-1].lastElementChild, container
          containers[level] = container
        else if containers.length > level+1
          containers.splice level+1, containers.length - (level+1)
        $.add containers[level], div
        count++
      count
    addSettingGroup = (root, name, beforeSetting) ->
      before = $("div[data-name=\"#{beforeSetting}\"]", root)
      return unless before
      heading = $.el 'h3',
        className: 'settings-group-heading'
        textContent: name
      $.before before, heading
    selectGroup = (obj, keys, baseLevel = 0) ->
      group = $.dict()
      for key in keys when (arr = obj[key])
        [defaultValue, description, level] = arr
        adjustedLevel = Math.max 0, (level or 0) - baseLevel
        group[key] = [defaultValue, description, adjustedLevel]
      group

    styleNames = Settings.stylingOptionNames
    for keyFS in categories
      continue unless (obj = Config.main[keyFS])

      if keyFS is 'Miscellaneous'
        lookup = Settings.getMainSettingLookup()
        for [legendTitle, keys] in [
          ['Browsing and Catalog', ['Redirect to HTTPS', 'JSON Index', 'Use <%= meta.name %> Catalog', 'Open Threads in New Tab', 'External Catalog']]
          ['UI', ['Announcement Hiding', 'Follow Cursor', 'Catalog Links']]
          ['Notifications', ['Desktop Notifications', 'Index Refresh Notifications', 'Show Updated Notifications', 'Posting Success Notifications']]
          ['Archives and Security', ['404 Redirect', 'Archive Report', 'Exempt Archives from Encryption']]
          ['Keyboard and Navigation', ['Keybinds', 'Comment Expansion', 'Thread Expansion', 'Index Navigation', 'Reply Navigation', 'Unique ID and Capcode Navigation', 'Normalize URL', 'Disable Autoplaying Sounds']]
          ['Compatibility', ['Disable Native Extension']]
        ]
          fs = $.el 'fieldset',
            `<%= html('<legend>${legendTitle}</legend>') %>`
          group = $.dict()
          for key in keys when lookup[key]
            group[key] = lookup[key]
          continue unless addCheckboxes(fs, group, (key) -> key not in styleNames)
          $.add section, fs
        continue

      if keyFS is 'Posting and Captchas'
        for [legendTitle, keys, baseLevel] in [
          ['Workflow', ['Quick Reply', 'Persistent QR', 'Auto Hide QR', 'Remember QR Size', 'Remember Spoiler', 'Show New Thread Option in Threads', 'Open Post in New Tab', 'Cooldown', 'Pass Link'], 0]
          ['Files and Submission', ['Randomize Filename', 'Auto-process Images', 'Show Upload Progress', 'Strip Video Audio'], 1]
          ['Captcha', ['Auto-load captcha', 'Post on Captcha Completion', 'Force Noscript Captcha', 'Stacked TCaptcha'], 1]
        ]
          fs = $.el 'fieldset',
            `<%= html('<legend>${legendTitle}</legend>') %>`
          group = selectGroup obj, keys, baseLevel
          continue unless addCheckboxes(fs, group, (key) -> key not in styleNames)
          if legendTitle is 'Captcha'
            $.add fs, $.el 'p',
              `<%= html('For more info on captcha options and issues, see the <a href="' + meta.captchaFAQ + '" target="_blank">captcha FAQ</a>.') %>`
          $.add section, fs
        continue

      legendTitle = if keyFS is 'Filtering' then 'Content Controls' else keyFS
      fs = $.el 'fieldset'
      unless keyFS in hideLegendFor
        $.extend fs, `<%= html('<legend>${legendTitle}</legend>') %>`
      continue unless addCheckboxes(fs, obj, (key) -> key not in styleNames)
      $.add section, fs

    if includeJSONIndex
      if root = $('div[data-name="JSON Index"] > .suboption-list', section)
        addCheckboxes root, Config.Index

    # Unsupported options
    if $.engine isnt 'gecko'
      if (el = $('div[data-name="Remember QR Size"]', section))
        el.hidden = true
    if $.perProtocolSettings or location.protocol isnt 'https:'
      if (el = $('div[data-name="Redirect to HTTPS"]', section))
        el.hidden = true

    $.get items, (items) ->
      for key, val of items
        inputs[key].checked = val
        inputs[key].parentNode.parentNode.dataset.checked = val
      return

    return unless includeHiddenCount
    div = $.el 'div',
      `<%= html('<button></button><span class="description">: Clear manually-hidden threads and posts on all boards. Reload the page to apply.') %>`
    button = $ 'button', div
    $.get {hiddenThreads: $.dict(), hiddenPosts: $.dict()}, ({hiddenThreads, hiddenPosts}) ->
      hiddenNum = 0
      for ID, site of hiddenThreads when ID isnt 'boards'
        for ID, board of site.boards
          hiddenNum += Object.keys(board).length
      for ID, board of hiddenThreads.boards
        hiddenNum += Object.keys(board).length
      for ID, site of hiddenPosts when ID isnt 'boards'
        for ID, board of site.boards
          for ID, thread of board
            hiddenNum += Object.keys(thread).length
      for ID, board of hiddenPosts.boards
        for ID, thread of board
          hiddenNum += Object.keys(thread).length
      button.textContent = "Hidden: #{hiddenNum}"
    $.on button, 'click', ->
      @textContent = 'Hidden: 0'
      $.get 'hiddenThreads', $.dict(), ({hiddenThreads}) ->
        if $.hasStorage and g.SITE.software is 'yotsuba'
          for boardID of hiddenThreads['4chan.org']?.boards
            localStorage.removeItem "4chan-hide-t-#{boardID}"
          for boardID of hiddenThreads.boards
            localStorage.removeItem "4chan-hide-t-#{boardID}"
        ($.delete ['hiddenThreads', 'hiddenPosts'])
    if stubs = $('input[name="Stubs"]', section)
      $.after stubs.parentNode.parentNode, div
    else
      $.add section, div

  addSelectFieldset: (section, title, rows) ->
    fs = $.el 'fieldset',
      `<%= html('<legend>${title}</legend>') %>`
    items = $.dict()
    inputs = $.dict()
    for row in rows
      div = $.el 'div'
      div.dataset.name = row.name
      div.dataset.settingTitle = row.label
      div.dataset.settingDescription = row.description or ''
      label = $.el 'label'
      select = $.el 'select',
        name: row.name
      for option in row.options
        select.appendChild $.el 'option',
          value: option[0]
          textContent: option[1]
      $.add label, [
        $.el 'span',
          className: 'setting-title'
          textContent: "#{row.label}: "
        select
      ]
      $.add div, [
        label
        $.el 'span',
          className: 'description'
          textContent: if row.description then ": #{row.description}" else ''
      ]
      $.on select, 'change', $.cb.value
      items[row.name] = Conf[row.name]
      inputs[row.name] = select
      $.add fs, div
    $.add section, fs
    $.get items, (items) ->
      for key, val of items
        inputs[key].value = val
      return

  addThreadWatcherFieldset: (section) ->
    fs = $.el 'fieldset',
      `<%= html('<legend>Thread Watcher</legend>') %>`

    items = $.dict()
    inputs = $.dict()

    for name, conf of Config.threadWatcher
      description = conf[1] or ''
      div = $.el 'div',
        `<%= html('<label><input type="checkbox" name="${name}"><span class="setting-title">${name}</span></label><span class="description">: <span class="setting-description">${description}</span></span>') %>`
      div.dataset.name = name
      div.dataset.settingTitle = name
      div.dataset.settingDescription = description
      input = $ 'input', div
      $.on input, 'change', $.cb.checked
      $.on input, 'change', -> @parentNode.parentNode.dataset.checked = @checked
      $.on input, 'change', ->
        return unless ThreadWatcher.enabled
        if @name in ['Current Board', 'Show Page', 'Show Unread Count', 'Show Site Prefix', 'Show OP Thumbnails']
          ThreadWatcher.refresh()
        if @name in ['Show Page', 'Show Unread Count', 'Auto Update Thread Watcher']
          ThreadWatcher.fetchAuto()
        if @name is 'Show OP Thumbnails' and @checked
          ThreadWatcher.fetchAllStatus()
      items[name] = Conf[name]
      inputs[name] = input
      $.add fs, div

    sizeDiv = $.el 'div',
      `<%= html('<label><span class="setting-title">Thumbnail Size: </span><input type="number" name="Thread Watcher Thumbnail Size" min="16" max="160" step="1"></label><span class="description">: Set OP thumbnail size (16-160px).</span>') %>`
    sizeDiv.dataset.name = 'Thread Watcher Thumbnail Size'
    sizeDiv.dataset.settingTitle = 'Thread Watcher Thumbnail Size'
    sizeDiv.dataset.settingDescription = 'Set OP thumbnail size (16-160px).'
    sizeInput = $ 'input', sizeDiv
    $.on sizeInput, 'change', ->
      size = parseInt(@value, 10)
      if isNaN(size)
        size = 40
      size = Math.max(16, Math.min(160, size))
      @value = size
      $.set @name, size
      Conf[@name] = size
      return unless ThreadWatcher.enabled
      ThreadWatcher.refresh()
    items['Thread Watcher Thumbnail Size'] = Conf['Thread Watcher Thumbnail Size']
    inputs['Thread Watcher Thumbnail Size'] = sizeInput
    $.add fs, sizeDiv

    $.add section, fs
    $.get items, (items) ->
      for key, val of items
        input = inputs[key]
        switch input.type
          when 'checkbox'
            input.checked = val
            input.parentNode.parentNode.dataset.checked = val
          else
            input.value = val
      return
    return

  main: (section) ->
    Settings.general section

  general: (section) ->
    Settings.renderMainGroups section,
      categories: ['Miscellaneous', 'Linkification', 'Menu']
      includeWarnings: true
      includeJSONIndex: true
      includeHiddenCount: false
      hideLegendFor: ['Miscellaneous']

  reading: (section) ->
    Settings.renderMainGroups section,
      categories: ['Monitoring', 'Quote Links', 'Filtering']
      includeWarnings: false
      includeJSONIndex: false
      includeHiddenCount: true
    Settings.addThreadWatcherFieldset section
    Settings.addSelectFieldset section, 'Thread Title',
      [
        {
          name: 'Thread Title'
          label: 'Title Content'
          description: 'Choose whether thread tabs use the original thread excerpt or the board title.'
          options: [
            ['excerpt', 'Original thread title']
            ['board', 'Board title']
          ]
        }
        {
          name: 'Unread Title Count'
          label: 'Unread Count'
          description: 'Controls how unread and quoted-you indicators appear in the tab title.'
          options: [
            ['always', 'Always show count']
            ['hide-zero', 'Hide zero count']
            ['quoted', 'Show quote marker']
            ['quoted-hide-zero', 'Quote marker and hide zero']
          ]
        }
      ]

  media: (section) ->
    Settings.renderMainGroups section,
      categories: ['Images and Videos']
      includeWarnings: false
      includeJSONIndex: false
      includeHiddenCount: false

  posting: (section) ->
    Settings.renderMainGroups section,
      categories: ['Posting and Captchas']
      includeWarnings: false
      includeJSONIndex: false
      includeHiddenCount: false

  styling: (section) ->
    items  = $.dict()
    inputs = $.dict()
    addCheckboxes = (root, obj) ->
      containers = [root]
      for key, arr of obj when arr instanceof Array
        description = arr[1] or ''
        div = $.el 'div',
          `<%= html('<label><input type="checkbox" name="${key}"><span class="setting-title">${key}</span></label><span class="description">: <span class="setting-description">${description}</span></span>') %>`
        div.dataset.name = key
        div.dataset.settingTitle = key
        div.dataset.settingDescription = description
        if keywords = Settings.searchKeywords[key]
          div.dataset.searchKeywords = keywords
        input = $ 'input', div
        $.on input, 'change', $.cb.checked
        $.on input, 'change', -> @parentNode.parentNode.dataset.checked = @checked
        items[key]  = Conf[key]
        inputs[key] = input
        level = arr[2] or 0
        if containers.length <= level
          container = $.el 'div', className: 'suboption-list'
          $.add containers[containers.length-1].lastElementChild, container
          containers[level] = container
        else if containers.length > level+1
          containers.splice level+1, containers.length - (level+1)
        $.add containers[level], div
      return

    fs = $.el 'fieldset',
      `<%= html('<legend>Display Options</legend>') %>`
    lookup = Settings.getMainSettingLookup()
    for [title, keys] in [
      ['Time and Formatting', ['Time Formatting', 'Relative Post Dates', 'Relative Date Title', 'File Info Formatting']]
      ['Board and ID Display', ['Custom Board Titles', 'Persistent Custom Board Titles', 'Color User IDs', 'Count Posts by ID']]
      ['Spoiler Display', ['Remove Spoilers', 'Reveal Spoilers']]
    ]
      group = $.dict()
      for key in keys when lookup[key]
        group[key] = lookup[key]
      continue unless Object.keys(group).length
      $.add fs, $.el 'h3',
        className: 'settings-group-heading'
        textContent: title
      addCheckboxes fs, group
    $.add section, fs

    $.extend section, `<%= readHTML('Styling.html') %>`
    Settings.setupSiteStyleMirror section
    warning.hidden = Conf[warning.dataset.feature] for warning in $$ '.warning', section

    for input in $$ '[name]', section when not (input.name of inputs)
      inputs[input.name] = input

    for name, input of inputs when name isnt 'Custom CSS'
      items[name] = Conf[name]
      event = if (
        input.nodeName is 'SELECT' or
        input.type in ['checkbox', 'radio'] or
        (input.nodeName is 'TEXTAREA' and name not of Settings)
      ) then 'change' else 'input'
      $.on input, event, $.cb[if input.type is 'checkbox' then 'checked' else 'value']
      $.on input, event, Settings[name] if name of Settings

    $.get items, (items) ->
      for key, val of items
        input = inputs[key]
        continue unless input
        input[if input.type is 'checkbox' then 'checked' else 'value'] = val
        if input.type is 'checkbox'
          input.parentNode.parentNode.dataset.checked = val
        input.hidden = false # XXX prevent Firefox from adding initialization to undo queue
        if key of Settings
          Settings[key].call input
        input._cssHlUpdate?()
      return

    customCSS = inputs['Custom CSS']
    customCSSHome = inputs['Custom CSS on Homepage']
    applyCSS = $ '#apply-css', section
    if customCSS and customCSSHome and inputs['usercss'] and applyCSS
      customCSS.checked = Conf['Custom CSS']
      customCSSHome.disabled = !Conf['Custom CSS']
      inputs['usercss'].disabled = !Conf['Custom CSS']
      applyCSS.disabled = !Conf['Custom CSS']
      $.on customCSS, 'change', Settings.togglecss
      $.on applyCSS,  'click',  ->
        Settings.flushCustomCSSEditor()
        CustomCSS.update()
    if resetGeneratedHighlights = $('.reset-generated-highlights', section)
      $.on resetGeneratedHighlights, 'click', Settings.resetGeneratedHighlightStyles

    Settings.refreshGeneratedHighlightStylesEditor()
    Settings.setupCSSHighlight inputs['usercss']

  setupSiteStyleMirror: (section) ->
    controls = $('.site-theme-controls', section)
    mirror = $('.site-style-mirror', section)
    nativeSelect = $.id 'styleSelector'
    unless controls and mirror and nativeSelect?.options?.length
      controls.hidden = true if controls
      return

    $.rmAll mirror
    options = []
    for option in nativeSelect.options
      options.push $.el 'option',
        value: option.value
        textContent: option.textContent
    $.add mirror, options
    mirror.value = nativeSelect.value

    dispatchChange = ->
      event = try
        new Event 'change',
          bubbles: true
      catch
        event = d.createEvent 'HTMLEvents'
        event.initEvent 'change', true, false
        event
      nativeSelect.dispatchEvent event

    $.on mirror, 'change', ->
      nativeSelect.value = mirror.value
      dispatchChange()

  flushCustomCSSEditor: ->
    textarea = $('textarea[name=usercss]', Settings.dialog)
    return unless textarea
    Conf['usercss'] = textarea.value
    $.set 'usercss', textarea.value

  export: ->
    Settings.flushCustomCSSEditor()
    # Make sure to export the most recent data, but don't overwrite existing `Conf` object.
    Conf2 = $.dict()
    $.extend Conf2, Conf
    $.get Conf2, (Conf2) ->
      # Don't export cached JSON data.
      delete Conf2['boardConfig']
      for key in [
        'Replace GIF'
        'Replace JPG'
        'Replace PNG'
        'Replace WEBM'
        'IP Count in Stats'
        'Page Count in Stats'
        'Quoted Title'
        'Hide Unread Count at (0)'
        'Remove Thread Excerpt'
      ]
        delete Conf2[key]
      (Settings.downloadExport {version: g.VERSION, date: Date.now(), Conf: Conf2})

  downloadExport: (data) ->
    blob = new Blob [JSON.stringify(data, null, 2)], {type: 'application/json'}
    url = URL.createObjectURL blob
    a = $.el 'a',
      download: "<%= meta.name %> v#{g.VERSION}-#{data.date}.json"
      href: url
    p = $ '.imp-exp-result', Settings.dialog
    $.rmAll p
    $.add p, a
    a.click()

  import: ->
    $('input[type=file]', @parentNode).click()

  onImport: ->
    return if not (file = @files[0])
    @value = null
    output = $('.imp-exp-result')
    unless confirm 'Your current settings will be entirely overwritten, are you sure?'
      output.textContent = 'Import aborted.'
      return

    reader = new FileReader()
    reader.onload = (e) ->
      try
        Settings.loadSettings $.dict.json(e.target.result), (err) ->
          if err
            output.textContent = 'Import failed due to an error.'
          else if confirm 'Import successful. Reload now?'
            window.location.reload()
      catch err
        output.textContent = 'Import failed due to an error.'
        c.error err.stack
    reader.readAsText file

  convertFrom:
    loadletter: (data) ->
      convertSettings = (data, map) ->
        for prevKey, newKey of map
          data.Conf[newKey] = data.Conf[prevKey] if newKey
          delete data.Conf[prevKey]
        data
      data = convertSettings data,
        # General confs
        'Disable 4chan\'s extension': 'Disable Native Extension'
        'Comment Auto-Expansion': ''
        'Remove Slug': ''
        'Always HTTPS': 'Redirect to HTTPS'
        'Check for Updates': ''
        'Recursive Filtering': 'Recursive Hiding'
        'Reply Hiding': 'Reply Hiding Buttons'
        'Thread Hiding': 'Thread Hiding Buttons'
        'Show Stubs': 'Stubs'
        'Image Auto-Gif': 'Replace Thumbnails'
        'Expand All WebM': 'Expand videos'
        'Reveal Spoilers': 'Reveal Spoiler Thumbnails'
        'Expand From Current': 'Expand from here'
        'Current Page': 'Detailed Thread Stats'
        'Current Page Position': ''
        'Alternative captcha': 'Use Recaptcha v1'
        'Alt index captcha': 'Use Recaptcha v1 on Index'
        'Auto Submit': 'Post on Captcha Completion'
        'Open Reply in New Tab': 'Open Post in New Tab'
        'Remember QR size': 'Remember QR Size'
        'Remember Subject': ''
        'Quote Inline': 'Quote Inlining'
        'Quote Preview': 'Quote Previewing'
        'Indicate OP quote': 'Mark OP Quotes'
        'Indicate You quote': 'Mark Quotes of You'
        'Indicate Cross-thread Quotes': 'Mark Cross-thread Quotes'
        # filter
        'uniqueid': 'uniqueID'
        'mod': 'capcode'
        'email': ''
        'country': 'flag'
        'md5': 'MD5'
        # keybinds
        'openEmptyQR': 'Open empty QR'
        'openQR': 'Open QR'
        'openOptions': 'Open settings'
        'close': 'Close'
        'spoiler': 'Spoiler tags'
        'sageru': 'Toggle sage'
        'code': 'Code tags'
        'sjis': 'SJIS tags'
        'submit': 'Submit QR'
        'watch': 'Watch'
        'update': 'Update'
        'unreadCountTo0': ''
        'expandAllImages': 'Expand images'
        'expandImage': 'Expand image'
        'zero': 'Front page'
        'nextPage': 'Next page'
        'previousPage': 'Previous page'
        'nextThread': 'Next thread'
        'previousThread': 'Previous thread'
        'expandThread': 'Expand thread'
        'openThreadTab': 'Open thread'
        'openThread': 'Open thread tab'
        'nextReply': 'Next reply'
        'previousReply': 'Previous reply'
        'hide': 'Hide'
        # updater
        'Scrolling': 'Auto Scroll'
        'Verbose': ''
      if 'Always CDN' of data.Conf
        data.Conf['fourchanImageHost'] = if data.Conf['Always CDN'] then 'i.4cdn.org' else ''
        delete data.Conf['Always CDN']
      data.Conf.sauces = data.Conf.sauces.replace /\$\d/g, (c) ->
        switch c
          when '$1'
            '%TURL'
          when '$2'
            '%URL'
          when '$3'
            '%MD5'
          when '$4'
            '%board'
          else
            c
      for key, val of Config.hotkeys when key of data.Conf
        data.Conf[key] = data.Conf[key].replace(/ctrl|alt|meta/g, (s) -> "#{s[0].toUpperCase()}#{s[1..]}").replace /(^|.+\+)[A-Z]$/g, (s) ->
          "Shift+#{s[0...-1]}#{s[-1..].toLowerCase()}"
      if data.WatchedThreads
        data.Conf['watchedThreads'] = $.dict.clone {'4chan.org': {boards: {}}}
        for boardID, threads of data.WatchedThreads
          for threadID, threadData of threads
            (data.Conf['watchedThreads']['4chan.org'].boards[boardID] or= $.dict())[threadID] = excerpt: threadData.textContent
      data

  upgrade: (data, version) ->
    changes = $.dict()
    set = (key, value) ->
      data[key] = changes[key] = value
    setD = (key, value) ->
      set key, value unless data[key]?
    addSauces = (sauces) ->
      if data['sauces']?
        sauces = sauces.filter (s) -> data['sauces'].indexOf(s.match(/[^#;\s]+|$/)[0]) < 0
        if sauces.length
          set 'sauces', data['sauces'] + '\n\n' + sauces.join('\n')
    addCSS = (css) ->
      set 'usercss', Config['usercss'] unless data['usercss']?
      if data['usercss'].indexOf(css) < 0
        set 'usercss', css + '\n\n' + data['usercss']
    # XXX https://github.com/greasemonkey/greasemonkey/issues/2600
    if (corrupted = (version[0] is '"'))
      try
        version = JSON.parse version
    # Fork (1.0.x) versions skip the legacy upstream 4chan-X migrations below.
    # They were one-time fixes for 4chan-X 1.11-1.14 upgrades; running them
    # every fork version bump duplicates usercss and re-coerces value types.
    return changes if /^1\.0\./.test(version)
    compareString = version.replace(/\d+/g, (x) -> ('0000'+x)[-5..])
    if compareString < '00001.00013.00014.00008'
      for key, val of data when typeof val is 'string' and typeof Conf[key] isnt 'string' and key not in ['Index Sort', 'Last Long Reply Thresholds 0', 'Last Long Reply Thresholds 1']
        corrupted = true
        break
    if corrupted
      for key, val of data when typeof val is 'string'
        try
          val2 = JSON.parse val
          set key, val2
    if compareString < '00001.00011.00008.00000'
      unless data['Fixed Thread Watcher']?
        set 'Fixed Thread Watcher', data['Toggleable Thread Watcher'] ? true
      unless data['Exempt Archives from Encryption']?
        set 'Exempt Archives from Encryption', data['Except Archives from Encryption'] ? false
    if compareString < '00001.00011.00010.00001'
      if data['selectedArchives']?
        uids = {"Moe":0,"4plebs Archive":3,"Nyafuu Archive":4,"Love is Over":5,"Rebecca Black Tech":8,"warosu":10,"fgts":15,"not4plebs":22,"DesuStorage":23,"fireden.net":24,"disabled":null}
        for boardID, record of data['selectedArchives']
          for type, name of record when $.hasOwn(uids, name)
            record[type] = uids[name]
        set 'selectedArchives', data['selectedArchives']
    if compareString < '00001.00011.00016.00000'
      if (rice = Config['usercss'].match(/\/\* Board title rice \*\/(?:\n.+)*/)[0])
        if data['usercss']? and data['usercss'].indexOf(rice) < 0
          set 'usercss', rice + '\n\n' + data['usercss']
    if compareString < '00001.00011.00017.00000'
      for key in ['Persistent QR', 'Color User IDs', 'Fappe Tyme', 'Werk Tyme', 'Highlight Posts Quoting You', 'Highlight Own Posts']
        set key, (key is 'Persistent QR') unless data[key]?
    if compareString < '00001.00011.00017.00006'
      if data['sauces']?
        set 'sauces', data['sauces'].replace(/^(#?\s*)http:\/\/iqdb\.org\//mg, '$1//iqdb.org/')
    if compareString < '00001.00011.00019.00003' and not Settings.dialog
      $.queueTask -> Settings.warnings.ads (item) -> new Notice 'warning', [item.childNodes...]
    if compareString < '00001.00011.00020.00003'
      for key, value of {'Inline Cross-thread Quotes Only': false, 'Pass Link': true}
        set key, value unless data[key]?
    if compareString < '00001.00011.00021.00003'
      unless data['Remember Your Posts']?
        set 'Remember Your Posts', data['Mark Quotes of You'] ? true
    if compareString < '00001.00011.00022.00000'
      if data['sauces']?
        set 'sauces', data['sauces'].replace(/^(#?\s*https:\/\/www\.google\.com\/searchbyimage\?image_url=%(?:IMG|URL))%3Fs\.jpg/mg, '$1')
        set 'sauces', data['sauces'].replace(/^#?\s*https:\/\/www\.google\.com\/searchbyimage\?image_url=%(?:IMG|T?URL)(?=$|;)/mg, '$&&safe=off')
    if compareString < '00001.00011.00022.00002'
      if not data['Use Recaptcha v1 in Reports']? and data['Use Recaptcha v1'] and not data['Use Recaptcha v2 in Reports']
        set 'Use Recaptcha v1 in Reports', true
    if compareString < '00001.00011.00024.00000'
      if data['JSON Navigation']? and not data['JSON Index']?
        set 'JSON Index', data['JSON Navigation']
    if compareString < '00001.00011.00026.00000'
      if data['Oekaki Links']? and not data['Edit Link']?
        set 'Edit Link', data['Oekaki Links']
      set 'Inline Cross-thread Quotes Only', true unless data['Inline Cross-thread Quotes Only']?
    if compareString < '00001.00011.00030.00000'
      if data['Quote Threading'] and not data['Thread Quotes']?
        set 'Thread Quotes', true
    if compareString < '00001.00011.00032.00000'
      if data['sauces']?
        set 'sauces', data['sauces'].replace(/^(#?\s*)http:\/\/3d\.iqdb\.org\//mg, '$1//3d.iqdb.org/')
      addSauces [
        '#https://desustorage.org/_/search/image/%sMD5/'
        '#https://boards.fireden.net/_/search/image/%sMD5/'
        '#https://foolz.fireden.net/_/search/image/%sMD5/'
        '#//www.gif-explode.com/%URL;types:gif'
      ]
    if compareString < '00001.00011.00035.00000'
      addSauces ['https://whatanime.ga/?auto&url=%IMG;text:wait']
    if compareString < '00001.00012.00000.00000'
      set 'Exempt Archives from Encryption', false unless data['Exempt Archives from Encryption']?
      set 'Show New Thread Option in Threads', false unless data['Show New Thread Option in Threads']?
      addCSS '#qr .persona .field {display: block !important;}' if data['Show Name and Subject']
      addCSS '#shortcut-qr {display: none;}' if data['QR Shortcut'] is false
      addCSS '.qr-link-container-bottom {display: none;}' if data['Bottom QR Link'] is false
    if compareString < '00001.00012.00000.00006'
      if data['sauces']?
        set 'sauces', data['sauces'].replace(/^(#?\s*)https:\/\/(?:desustorage|cuckchan)\.org\//mg, '$1https://desuarchive.org/')
    if compareString < '00001.00012.00001.00000'
      if not data['Persistent Thread Watcher']? and data['Toggleable Thread Watcher']?
        set 'Persistent Thread Watcher', not data['Toggleable Thread Watcher']
    if compareString < '00001.00012.00003.00000'
      for key in ['Image Hover in Catalog', 'Auto Watch', 'Auto Watch Reply']
        setD key, false
    if compareString < '00001.00013.00001.00002'
      addSauces ['#//www.bing.com/images/search?q=imgurl:%IMG&view=detailv2&iss=sbi#enterInsights']
    if compareString < '00001.00013.00005.00000'
      if data['sauces']?
        set 'sauces', data['sauces'].replace(/^(#?\s*)http:\/\/regex\.info\/exif\.cgi/mg, '$1http://exif.regex.info/exif.cgi')
      addSauces Config['sauces'].match(/# Known filename formats:(?:\n.+)*|$/)[0].split('\n')
    if compareString < '00001.00013.00007.00002'
      setD 'Require OP Quote Link', true
    if compareString < '00001.00013.00008.00000'
      setD 'Download Link', true
    if compareString < '00001.00013.00009.00003'
      if data['jsWhitelist']?
        list = data['jsWhitelist'].split('\n')
        if 'https://cdnjs.cloudflare.com' not in list and 'https://cdn.mathjax.org' in list
          set 'jsWhitelist', data['jsWhitelist'] + '\n\nhttps://cdnjs.cloudflare.com'
    if compareString < '00001.00014.00000.00006'
      if data['siteSoftware']?
        set 'siteSoftware', data['siteSoftware'] + '\n4cdn.org yotsuba'
    if compareString < '00001.00014.00003.00002'
      if data['sauces']?
        set 'sauces', data['sauces'].replace(/^(#?\s*)https:\/\/whatanime\.ga\//mg, '$1https://trace.moe/')
    if compareString < '00001.00014.00004.00004'
      if data['siteSoftware']? and !/^4channel\.org yotsuba$/m.test(data['siteSoftware'])
        set 'siteSoftware', data['siteSoftware'] + '\n4channel.org yotsuba'
    if compareString < '00001.00014.00005.00000'
      for db in DataBoard.keys
        if data[db]?.boards
          {boards, lastChecked} = data[db]
          data[db]['4chan.org'] = {boards, lastChecked}
          delete data[db].boards
          delete data[db].lastChecked
          set db, data[db]
      if data['siteSoftware']? and not data['siteProperties']?
        siteProperties = $.dict()
        for line in data['siteSoftware'].split('\n')
          [hostname, software] = line.split(' ')
          siteProperties[hostname] = {software}
        set 'siteProperties', siteProperties
    if compareString < '00001.00014.00006.00006'
      if data['sauces']?
        set 'sauces', data['sauces'].replace(
          /\/\/%\$1\.deviantart\.com\/gallery\/#\/d%\$2;regexp:\/\^\\w\+_by_\(\\w\+\)-d\(\[\\da-z\]\+\)\//g,
          '//www.deviantart.com/gallery/#/d%$1%$2;regexp:/^\\w+_by_\\w+[_-]d([\\da-z]{6})\\b|^d([\\da-z]{6})-[\\da-z]{8}-/'
        )
    if compareString < '00001.00014.00008.00000'
      if data['sauces']?
        set 'sauces', data['sauces'].replace(
          /https:\/\/www\.yandex\.com\/images\/search/g,
          'https://yandex.com/images/search'
        )
    if compareString < '00001.00014.00009.00000'
      if data['sauces']?
        set 'sauces', data['sauces'].replace(/^(#?\s*)(?:http:)?\/\/(www\.pixiv\.net|www\.deviantart\.com|imgur\.com|flickr\.com)\//mg, '$1https://$2/')
        set 'sauces', data['sauces'].replace(/https:\/\/yandex\.com\/images\/search\?rpt=imageview&img_url=%IMG/g, 'https://yandex.com/images/search?rpt=imageview&url=%IMG')
    if compareString < '00001.00014.00009.00001'
      if data['Use Faster Image Host']? and not data['fourchanImageHost']?
        set 'fourchanImageHost', (if data['Use Faster Image Host'] then 'i.4cdn.org' else '')
    if compareString < '00001.00014.00010.00001'
      unless data['Filter in Native Catalog']?
        set 'Filter in Native Catalog', false
    if compareString < '00001.00014.00012.00008'
      unless data['boardnav']?
        set 'boardnav', """
          [ toggle-all ]
          a-replace
          c-replace
          g-replace
          k-replace
          v-replace
          vg-replace
          vr-replace
          ck-replace
          co-replace
          fit-replace
          jp-replace
          mu-replace
          sp-replace
          tv-replace
          vp-replace
          [external-text:"FAQ","<%= meta.faq %>"]
        """
    if compareString < '00001.00014.00016.00001'
      if data['archiveLists']?
        set 'archiveLists', data['archiveLists'].replace('https://mayhemydg.github.io/archives.json/archives.json', 'https://nstepien.github.io/archives.json/archives.json')
    if compareString < '00001.00014.00016.00007'
      if data['sauces']?
        set 'sauces', data['sauces'].replace(
          /https:\/\/www\.deviantart\.com\/gallery\/#\/d%\$1%\$2;regexp:\/\^\\w\+_by_\\w\+\[_-\]d\(\[\\da-z\]\{6\}\)\\b\|\^d\(\[\\da-z\]\{6\}\)-\[\\da-z\]\{8\}-\//g,
          'javascript:void(open("https://www.deviantart.com/"+%$1.replace(/_/g,"-")+"/art/"+parseInt(%$2,36)));regexp:/^\\w+_by_(\\w+)[_-]d([\\da-z]{6})\\b/'
        ).replace(
          /\/\/imgops\.com\/%URL/g
          '//imgops.com/start?url=%URL'
        )
    if compareString < '00001.00014.00017.00002'
      if data['jsWhitelist']?
        set 'jsWhitelist', data['jsWhitelist'] + '\n\nhttps://hcaptcha.com\nhttps://*.hcaptcha.com'
    if compareString < '00001.00014.00020.00004'
      if data['archiveLists']?
        set 'archiveLists', data['archiveLists'].replace('https://nstepien.github.io/archives.json/archives.json', 'https://4chenz.github.io/archives.json/archives.json')
    if compareString < '00001.00014.00022.00003'
      if data['sauces']?
        set 'sauces', data['sauces'].replace(/^#?\s*https:\/\/www\.google\.com\/searchbyimage\?image_url=%(IMG|T?URL)&safe=off(?=$|;)/mg, 'https://www.google.com/searchbyimage?sbisrc=4chanx&image_url=%$1&safe=off')
        if compareString is '00001.00014.00022.00002' and not /\bsbisrc=/.test(data['sauces'])
          set 'sauces', data['sauces'].replace(/^#?\s*https:\/\/lens\.google\.com\/uploadbyurl\?url=%(IMG|T?URL)(?=$|;)/m, 'https://www.google.com/searchbyimage?sbisrc=4chanx&image_url=%$1&safe=off')
      addSauces [
        '#https://lens.google.com/uploadbyurl?url=%IMG;text:lens'
      ]
    unless data['Replace Thumbnails']?
      set 'Replace Thumbnails', !!(data['Replace GIF'] or data['Replace JPG'] or data['Replace PNG'] or data['Replace WEBM'])
    unless data['Detailed Thread Stats']?
      set 'Detailed Thread Stats', !!(data['IP Count in Stats'] ? true) or !!(data['Page Count in Stats'] ? true)
    unless data['Thread Title']?
      set 'Thread Title', if data['Remove Thread Excerpt'] then 'board' else 'excerpt'
    unless data['Unread Title Count']?
      quoted = !!data['Quoted Title']
      hideZero = !!data['Hide Unread Count at (0)']
      set 'Unread Title Count', if quoted and hideZero
        'quoted-hide-zero'
      else if quoted
        'quoted'
      else if hideZero
        'hide-zero'
      else
        'always'
    changes

  loadSettings: (data, cb) ->
    if data.version.split('.')[0] is '2' and "Disable 4chan's extension" of data.Conf # https://github.com/loadletter/4chan-eX
      data = Settings.convertFrom.loadletter data
    else if data.version isnt g.VERSION
      Settings.upgrade data.Conf, data.version
    $.clear (err) ->
      return cb err if err
      $.set data.Conf, cb

  reset: ->
    if confirm 'Your current settings will be entirely wiped, are you sure?'
      $.clear (err) ->
        if err
          $('.imp-exp-result').textContent = 'Import failed due to an error.'
        else if confirm 'Reset successful. Reload now?'
          window.location.reload()

  filters: (section) ->
    tabs = $.el 'div',
      className: 'settings-subnav'
    advancedTab = $.el 'a',
      className: 'settings-subnav-tab'
      textContent: 'Advanced'
      href: 'javascript:;'
    filteredTab = $.el 'a',
      className: 'settings-subnav-tab'
      textContent: 'Filtered'
      href: 'javascript:;'
    simpleTab = $.el 'a',
      className: 'settings-subnav-tab'
      textContent: 'Simple'
      href: 'javascript:;'
    $.add tabs, [simpleTab, advancedTab, filteredTab]

    advancedPanel = $.el 'div'
    simplePanel = $.el 'div'
    filteredPanel = $.el 'div'
    previewPanel = $.el 'div'
    previewState =
      panel: previewPanel
      simpleTbody: null
      advancedType: null
      advancedTextarea: null
    Settings.filtersPreviewState = previewState
    Settings.filter advancedPanel, previewState
    Settings.easyFilters simplePanel, previewState
    $.add filteredPanel, previewPanel
    advancedPanel.hidden = true
    simplePanel.hidden = true
    filteredPanel.hidden = true
    $.add section, [tabs, simplePanel, advancedPanel, filteredPanel]

    openMode = (mode) ->
      simplePanel.hidden = mode isnt 'simple'
      advancedPanel.hidden = mode isnt 'advanced'
      filteredPanel.hidden = mode isnt 'filtered'
      $.rmClass simpleTab, 'settings-subnav-tab-selected'
      $.rmClass advancedTab, 'settings-subnav-tab-selected'
      $.rmClass filteredTab, 'settings-subnav-tab-selected'
      $.addClass (
        if mode is 'simple'
          simpleTab
        else if mode is 'advanced'
          advancedTab
        else
          filteredTab
      ), 'settings-subnav-tab-selected'
      $.set 'settings.filtersMode', mode

    $.on simpleTab, 'click', -> openMode 'simple'
    $.on advancedTab, 'click', -> openMode 'advanced'
    $.on filteredTab, 'click', -> openMode 'filtered'
    $.get 'settings.filtersMode', 'simple', (item) ->
      mode = Settings.forcedFiltersMode or item['settings.filtersMode']
      delete Settings.forcedFiltersMode
      mode = 'simple' unless mode in ['simple', 'advanced', 'filtered']
      openMode mode

  filter: (section, previewState) ->
    $.extend section, `<%= readHTML('Filter-select.html') %>`
    select = $ 'select', section
    select.filterPreviewState = previewState
    $.on select, 'change', Settings.selectFilter
    Settings.selectFilter.call select

  easyFilterTypes: [
    ['General', 'general']
    ['Post Number', 'postID']
    ['Name', 'name']
    ['Unique ID', 'uniqueID']
    ['Tripcode', 'tripcode']
    ['Capcode', 'capcode']
    ['Pass Date', 'pass']
    ['Email', 'email']
    ['Subject', 'subject']
    ['Comment', 'comment']
    ['Flag', 'flag']
    ['Filename', 'filename']
    ['Dimensions', 'dimensions']
    ['Filesize', 'filesize']
    ['Image MD5', 'MD5']
  ]

  easyFilters: (section, previewState) ->
    $.extend section, `<%= readHTML('SimpleFilters.html') %>`
    tbody = $('tbody', section)
    addButton = $('.easy-filter-add', section)
    saveButton = $('.easy-filter-save', section)
    status = $('.easy-filter-status', section)
    previewState.simpleTbody = tbody if previewState

    markDirty = ->
      status.textContent = 'Unsaved changes.'
      Settings.refreshCombinedFilterPreview previewState

    save = ->
      rules = Settings.collectEasyFilters tbody
      serialized = JSON.stringify rules
      $.set 'easyFilters', serialized
      Conf['easyFilters'] = serialized
      status.textContent = "Saved #{rules.length} rule#{if rules.length is 1 then '' else 's'}."
      Settings.refreshCombinedFilterPreview previewState

    addRow = (rule={}) ->
      row = Settings.easyFilterRow(rule, markDirty)
      $.add tbody, row
      row

    rules = Settings.parseEasyFilters()
    if rules.length
      addRow(rule) for rule in rules
    else
      addRow
        enabled: true
        hide: true
        type: 'tripcode'

    $.on addButton, 'click', ->
      row = addRow
        enabled: true
        hide: true
        type: 'tripcode'
      patternInput = $('.easy-filter-pattern', row)
      if patternInput
        patternInput.focus()
        patternInput.select()
      markDirty()

    $.on saveButton, 'click', save

    status.textContent = "Loaded #{rules.length} rule#{if rules.length is 1 then '' else 's'}."
    Settings.refreshCombinedFilterPreview previewState

  parseEasyFilters: ->
    rules = []
    if Conf['easyFilters'] instanceof Array
      rules = Conf['easyFilters']
    else if typeof Conf['easyFilters'] is 'string' and Conf['easyFilters'].trim()
      try
        rules = JSON.parse Conf['easyFilters']
      catch
        rules = []
    return [] unless rules instanceof Array

    rules.map (rule) ->
      return {} unless rule and typeof rule is 'object'

      type = if rule.type of Config.filter then rule.type else switch rule.field
        when 'title'
          'subject'
        when 'body'
          'comment'
        when 'name'
          'name'
        else
          'general'

      hide = if rule.hide?
        !!rule.hide
      else
        ['highlight', 'notify'].indexOf(rule.action) < 0

      {
        enabled: if rule.enabled? then !!rule.enabled else true
        pattern: if typeof rule.pattern is 'string' then rule.pattern else if typeof rule.match is 'string' then rule.match else ''
        boards: if typeof rule.boards is 'string' then rule.boards else ''
        type: type
        color: if typeof rule.color is 'string' then rule.color else ''
        auto: if rule.auto? then !!rule.auto else false
        hide: hide
      }

  easyFilterRow: (rule, markDirty) ->
    tr = $.el 'tr',
      innerHTML: """
        <td><input class="easy-filter-enabled" type="checkbox"></td>
        <td><input class="field easy-filter-pattern" type="text"></td>
        <td><input class="field easy-filter-boards" type="text" placeholder="all or g,v"></td>
        <td><select class="easy-filter-type"></select></td>
        <td><input class="field easy-filter-color" type="text" placeholder="highlight class"></td>
        <td><input class="easy-filter-auto" type="checkbox" title="Move highlighted OPs to top"></td>
        <td><input class="easy-filter-hide" type="checkbox"></td>
        <td><button class="easy-filter-remove" type="button" title="Remove">\u00d7</button></td>
      """

    typeSelect = $('.easy-filter-type', tr)
    for [label, value] in Settings.easyFilterTypes
      $.add typeSelect, $.el 'option', {textContent: label, value}

    enabledInput = $('.easy-filter-enabled', tr)
    patternInput = $('.easy-filter-pattern', tr)
    boardsInput = $('.easy-filter-boards', tr)
    colorInput = $('.easy-filter-color', tr)
    autoInput = $('.easy-filter-auto', tr)
    hideInput = $('.easy-filter-hide', tr)
    removeButton = $('.easy-filter-remove', tr)

    enabledInput.checked = if rule.enabled? then !!rule.enabled else true
    patternInput.value = rule.pattern or ''
    boardsInput.value = rule.boards or ''
    typeSelect.value = if rule.type of Config.filter then rule.type else 'general'
    colorInput.value = rule.color or ''
    autoInput.checked = !!rule.auto
    hideInput.checked = if rule.hide? then !!rule.hide else true

    for input in $$ 'input, select', tr
      $.on input, 'change', markDirty
      $.on input, 'input', markDirty if input.type in ['text']

    $.on removeButton, 'click', ->
      $.rm tr
      markDirty()

    tr

  collectEasyFilters: (tbody) ->
    rules = []
    for tr in $$ 'tr', tbody
      pattern = $('.easy-filter-pattern', tr).value.trim()
      continue unless pattern
      type = $('.easy-filter-type', tr).value
      rules.push
        enabled: $('.easy-filter-enabled', tr).checked
        pattern: pattern
        boards: $('.easy-filter-boards', tr).value.trim()
        type: if type of Config.filter then type else 'general'
        color: $('.easy-filter-color', tr).value.trim()
        auto: $('.easy-filter-auto', tr).checked
        hide: $('.easy-filter-hide', tr).checked
    rules

  easyFilterRuleFromRow: (tr) ->
    pattern = $('.easy-filter-pattern', tr).value.trim()
    return null unless pattern
    type = $('.easy-filter-type', tr).value
    {
      enabled: $('.easy-filter-enabled', tr).checked
      pattern: pattern
      boards: $('.easy-filter-boards', tr).value.trim()
      type: if type of Config.filter then type else 'general'
      color: $('.easy-filter-color', tr).value.trim()
      auto: $('.easy-filter-auto', tr).checked
      hide: $('.easy-filter-hide', tr).checked
    }

  easyFilterRuleToLine: (rule) ->
    return null unless rule?.enabled
    match = rule.pattern.trim()
    return null unless match

    flags = if rule.caseSensitive then '' else 'i'
    line = "/#{Filter.escape(match)}/#{flags}"

    options = []
    if typeof rule.boards is 'string' and (boards = rule.boards.trim())
      options.push "boards:#{boards}"

    type = if rule.type of Config.filter then rule.type else switch rule.field
      when 'title'
        'subject'
      when 'body'
        'comment'
      when 'name'
        'name'
      else
        'general'
    options.push "type:#{if type is 'general' then 'subject,name,comment' else type}"

    hide = if rule.hide?
      !!rule.hide
    else
      ['highlight', 'notify'].indexOf(rule.action) < 0

    unless hide
      if typeof rule.color is 'string' and (color = rule.color.trim())
        options.push "highlight:#{color}"
      else
        options.push 'highlight'
      options.push "top:#{if rule.auto then 'yes' else 'no'}"

    if rule.action is 'notify'
      options.push 'notify'

    line += ";#{options.join(';')}" if options.length
    line

  renderEasyFilterPreview: (tbody, panel) ->
    $.rmAll panel
    unless g.BOARD?.threads and g.VIEW in ['index', 'thread', 'catalog']
      $.add panel, $.el 'div',
        className: 'filter-stats-empty'
        textContent: 'Thread match preview is available on board and catalog pages.'
      return

    entries = Settings.filterPreviewEntries()
    unless entries.length
      $.add panel, $.el 'div',
        className: 'filter-stats-empty'
        textContent: 'No loaded thread data to preview.'
      return

    stats = []
    totalMatches = 0
    totalHidden = 0
    activeRules = 0
    rowNo = 0
    for tr in $$ 'tr', tbody
      rowNo++
      rule = Settings.easyFilterRuleFromRow tr
      continue unless rule
      lineText = Settings.easyFilterRuleToLine rule
      unless lineText
        stats.push
          rowNo: rowNo
          rule: rule
          disabled: true
        continue

      activeRules++
      parsed = Settings.parseFilterPreviewLine 'general', lineText
      if parsed?.invalid
        stats.push
          rowNo: rowNo
          rule: rule
          invalid: parsed.invalid
        continue

      result = Settings.collectFilterPreviewMatches parsed, entries
      totalMatches += result.matches.length
      totalHidden += result.hiddenThreadCount
      stats.push
        rowNo: rowNo
        rule: rule
        matches: result.matches
        hiddenThreadCount: result.hiddenThreadCount

    unless stats.length
      $.add panel, $.el 'div',
        className: 'filter-stats-empty'
        textContent: 'Add a pattern to preview thread matches.'
      return

    summary = $.el 'div',
      className: 'filter-stats-summary'
      textContent: "#{activeRules} active rule#{if activeRules is 1 then '' else 's'}, #{totalMatches} matching thread#{if totalMatches is 1 then '' else 's'}, #{totalHidden} hidden thread#{if totalHidden is 1 then '' else 's'}."
    $.add panel, summary

    maxThreads = 50
    for stat in stats
      row = $.el 'div', className: 'filter-stat-row'
      ruleText = "#{stat.rule.type}: #{stat.rule.pattern}"
      ruleText = "#{ruleText[...117]}..." if ruleText.length > 120

      if stat.disabled
        $.add row, [
          $.el 'span',
            className: 'filter-stat-count'
            textContent: "Rule #{stat.rowNo}: disabled"
          $.tn ' '
          $.el 'code',
            textContent: ruleText
        ]
        $.add panel, row
        continue

      if stat.invalid
        $.add row, $.el 'div',
          className: 'filter-stat-invalid'
          textContent: "Rule #{stat.rowNo}: invalid regex (#{stat.invalid})"
        $.add panel, row
        continue

      matchCount = stat.matches.length
      summaryText = "Rule #{stat.rowNo}: #{matchCount} matching thread#{if matchCount is 1 then '' else 's'}"
      if stat.hiddenThreadCount
        summaryText += ", #{stat.hiddenThreadCount} hidden"

      if matchCount
        details = $.el 'details', className: 'filter-stat'
        summaryEl = $.el 'summary'
        $.add summaryEl, [
          $.el 'span',
            className: 'filter-stat-count'
            textContent: summaryText
          $.tn ' '
          $.el 'code',
            textContent: ruleText
        ]
        $.add details, summaryEl

        list = $.el 'ul', className: 'filter-stat-threads'
        for match, idx in stat.matches when idx < maxThreads
          {entry, hidesThread} = match
          {href, text} = Settings.filterPreviewThreadLink entry
          link = $.el 'a',
            href: href
            textContent: text
          li = $.el 'li'
          $.add li, link
          if hidesThread
            $.add li, $.tn ' (hidden)'
          $.add list, li
        if stat.matches.length > maxThreads
          $.add list, $.el 'li',
            className: 'filter-stat-more'
            textContent: "...and #{stat.matches.length - maxThreads} more."
        $.add details, list
        $.add row, details
      else
        $.add row, [
          $.el 'span',
            className: 'filter-stat-count'
            textContent: summaryText
          $.tn ' '
          $.el 'code',
            textContent: ruleText
        ]
      $.add panel, row
    return

  selectFilter: ->
    div = @nextElementSibling
    previewState = @filterPreviewState
    if (name = @value) isnt 'guide'
      return unless $.hasOwn(Config.filter, name)
      $.rmAll div
      ta = $.el 'textarea',
        name: name
        className: 'field'
        spellcheck: false
      $.on ta, 'change', $.cb.value
      $.get name, Conf[name], (item) ->
        ta.value = item[name]
        $.add div, ta
        Settings.addFilterStats name, ta, div, previewState
      return
    filterTypes = Object.keys(Config.filter).filter((x) -> x isnt 'general').map (x, i) ->
      `<%= html('?{i}{,}<wbr>${x}') %>`
    $.extend div, `<%= readHTML('Filter-guide.html') %>`
    $('.warning', div).hidden = Conf['Filter']

  addFilterStats: (type, textarea, container, previewState) ->
    if previewState
      previewState.advancedType = type
      previewState.advancedTextarea = textarea
      refresh = ->
        Settings.refreshCombinedFilterPreview previewState
      $.on textarea, 'input', refresh
      $.on textarea, 'change', refresh
      refresh()
      return

    return unless container
    panel = $.el 'div', className: 'filter-stats'
    $.add container, panel
    timer = 0
    refresh = ->
      clearTimeout timer if timer
      timer = setTimeout((->
        Settings.renderFilterStats type, textarea, panel
      ), 120)
    $.on textarea, 'input', refresh
    $.on textarea, 'change', refresh
    Settings.renderFilterStats type, textarea, panel

  refreshCombinedFilterPreview: (previewState=Settings.filtersPreviewState) ->
    panel = previewState?.panel
    return unless panel
    $.rmAll panel

    if !previewState.simpleTbody and !previewState.advancedTextarea
      $.add panel, $.el 'div',
        className: 'filter-stats-empty'
        textContent: 'No filters loaded yet.'
      return

    if previewState.simpleTbody
      simpleGroup = $.el 'div', className: 'filter-preview-group'
      $.add simpleGroup, $.el 'div',
        className: 'filter-preview-heading'
        textContent: 'Simple Filters'
      simplePanel = $.el 'div', className: 'filter-stats'
      $.add simpleGroup, simplePanel
      Settings.renderEasyFilterPreview previewState.simpleTbody, simplePanel
      $.add panel, simpleGroup

    if previewState.advancedTextarea
      advancedGroup = $.el 'div', className: 'filter-preview-group'
      advancedLabel = if previewState.advancedType then "Advanced Filters (#{previewState.advancedType})" else 'Advanced Filters'
      $.add advancedGroup, $.el 'div',
        className: 'filter-preview-heading'
        textContent: advancedLabel
      advancedPanel = $.el 'div', className: 'filter-stats'
      $.add advancedGroup, advancedPanel
      Settings.renderFilterStats previewState.advancedType, previewState.advancedTextarea, advancedPanel
      $.add panel, advancedGroup

  renderFilterStats: (type, textarea, panel) ->
    $.rmAll panel
    unless g.BOARD?.threads and g.VIEW in ['index', 'thread', 'catalog']
      $.add panel, $.el 'div',
        className: 'filter-stats-empty'
        textContent: 'Thread match preview is available on board and catalog pages.'
      return

    entries = Settings.filterPreviewEntries()
    unless entries.length
      $.add panel, $.el 'div',
        className: 'filter-stats-empty'
        textContent: 'No loaded thread data to preview.'
      return

    lines = textarea.value.split '\n'
    stats = []
    totalMatches = 0
    totalHidden = 0

    for line, i in lines
      trimmed = line.trim()
      continue unless trimmed

      parsed = Settings.parseFilterPreviewLine type, line
      continue if parsed?.skip

      if parsed?.invalid
        stats.push
          lineNo: i + 1
          line: line
          invalid: parsed.invalid
        continue

      result = Settings.collectFilterPreviewMatches parsed, entries
      totalMatches += result.matches.length
      totalHidden += result.hiddenThreadCount
      stats.push
        lineNo: i + 1
        line: line
        matches: result.matches
        hiddenThreadCount: result.hiddenThreadCount

    unless stats.length
      $.add panel, $.el 'div',
        className: 'filter-stats-empty'
        textContent: 'No filter lines to preview.'
      return

    summary = $.el 'div',
      className: 'filter-stats-summary'
      textContent: "#{stats.length} line#{if stats.length is 1 then '' else 's'}, #{totalMatches} matching thread#{if totalMatches is 1 then '' else 's'}, #{totalHidden} hidden thread#{if totalHidden is 1 then '' else 's'}."
    $.add panel, summary

    maxThreads = 50
    for stat in stats
      row = $.el 'div', className: 'filter-stat-row'
      if stat.invalid
        $.add row, $.el 'div',
          className: 'filter-stat-invalid'
          textContent: "Line #{stat.lineNo}: invalid regex (#{stat.invalid})"
        $.add panel, row
        continue

      lineText = stat.line.trim()
      lineText = "#{lineText[...117]}..." if lineText.length > 120
      matchCount = stat.matches.length
      summaryText = "Line #{stat.lineNo}: #{matchCount} matching thread#{if matchCount is 1 then '' else 's'}"
      if stat.hiddenThreadCount
        summaryText += ", #{stat.hiddenThreadCount} hidden"

      if matchCount
        details = $.el 'details', className: 'filter-stat'
        summaryEl = $.el 'summary'
        $.add summaryEl, [
          $.el 'span',
            className: 'filter-stat-count'
            textContent: summaryText
          $.tn ' '
          $.el 'code',
            textContent: lineText
        ]
        $.add details, summaryEl

        list = $.el 'ul', className: 'filter-stat-threads'
        for match, idx in stat.matches when idx < maxThreads
          {entry, hidesThread} = match
          {href, text} = Settings.filterPreviewThreadLink entry
          link = $.el 'a',
            href: href
            textContent: text
          li = $.el 'li'
          $.add li, link
          if hidesThread
            $.add li, $.tn ' (hidden)'
          $.add list, li
        if stat.matches.length > maxThreads
          $.add list, $.el 'li',
            className: 'filter-stat-more'
            textContent: "...and #{stat.matches.length - maxThreads} more."
        $.add details, list
        $.add row, details
      else
        $.add row, [
          $.el 'span',
            className: 'filter-stat-count'
            textContent: summaryText
          $.tn ' '
          $.el 'code',
            textContent: lineText
        ]

      $.add panel, row
    return

  parseFilterPreviewLine: (key, line) ->
    return {skip: true} if line[0] is '#'
    return {skip: true} unless (regexpMatch = line.match /\/(.*)\/(\w*)/)

    filter = line.replace regexpMatch[0], ''

    boards = Filter.parseBoards filter.match(/(?:^|;)\s*boards:([^;]+)/)?[1]
    excludes = Filter.parseBoards filter.match(/(?:^|;)\s*exclude:([^;]+)/)?[1]

    isstring = key in ['uniqueID', 'MD5']
    regexp = regexpMatch[1]
    unless isstring
      try
        regexp = RegExp regexpMatch[1], regexpMatch[2]
      catch err
        return {invalid: err.message}

    op = filter.match(/(?:^|;)\s*op:(no|only)/)?[1] or ''
    mask = $.getOwn({'no': 1, 'only': 2}, op) or 0

    file = filter.match(/(?:^|;)\s*file:(no|only)/)?[1] or ''
    mask = mask | ($.getOwn({'no': 4, 'only': 8}, file) or 0)

    noti = /(?:^|;)\s*notify/.test filter
    hl = /(?:^|;)\s*highlight/.test filter
    hide = !(hl or noti)

    keys = if key is 'general'
      if (types = filter.match /(?:^|;)\s*type:([^;]*)/)
        types[1].split(',')
      else
        ['subject', 'name', 'filename', 'comment']
    else
      [key]

    {
      regexp
      isstring
      boards
      excludes
      mask
      hide
      keys
    }

  collectFilterPreviewMatches: (parsed, entries) ->
    matches = []
    hiddenThreadCount = 0

    for entry in entries
      threadMatched = false
      hidesThread = false
      for post in entry.posts
        continue unless Settings.filterPreviewMatchesPost parsed, post
        threadMatched = true
        if parsed.hide and !post.isReply and !QuoteYou.isYou(post)
          hidesThread = true
      if threadMatched
        matches.push {entry, hidesThread}
        hiddenThreadCount++ if hidesThread

    {matches, hiddenThreadCount}

  filterPreviewMatchesPost: (parsed, post) ->
    mask = (if post.isReply then 2 else 1)
    mask = mask | (if post.file then 4 else 8)
    board = "#{post.siteID}/#{post.boardID}"
    site = "#{post.siteID}/*"

    return false if (
      (parsed.boards and !(parsed.boards[board] or parsed.boards[site])) or
      (parsed.excludes and (parsed.excludes[board] or parsed.excludes[site])) or
      (parsed.mask & mask)
    )

    for key in parsed.keys
      for value in Filter.values(key, post)
        if parsed.isstring
          return true if parsed.regexp is value
        else
          parsed.regexp.lastIndex = 0
          return true if parsed.regexp.test(value)
    false

  filterPreviewEntries: ->
    entries = []

    if g.VIEW is 'index' and Index?.parsedThreads
      for threadID, parsed of Index.parsedThreads
        thread = g.BOARD?.threads?.get?(+threadID) or g.BOARD?.threads?.get?(threadID)
        posts = []
        if thread?.posts
          thread.posts.forEach (post) ->
            return if post.isClone or post.isFetchedQuote
            posts.push post
        posts.push parsed unless posts.length
        entries.push
          id: +threadID
          boardID: parsed.boardID
          siteID: parsed.siteID
          thread: thread
          op: parsed
          posts: posts
      return entries

    if g.VIEW is 'catalog' and Filter?.catalogData
      for threadID, data of Filter.catalogData
        parsed = g.SITE.Build.parseJSON data, g.BOARD
        thread = g.BOARD?.threads?.get?(+threadID) or g.BOARD?.threads?.get?(threadID)
        posts = []
        if thread?.posts
          thread.posts.forEach (post) ->
            return if post.isClone or post.isFetchedQuote
            posts.push post
        posts.push parsed unless posts.length
        entries.push
          id: +threadID
          boardID: parsed.boardID
          siteID: parsed.siteID
          thread: thread
          op: parsed
          posts: posts
      return entries

    if g.BOARD?.threads
      g.BOARD.threads.forEach (thread) ->
        return unless thread?.OP and !thread.OP.isFetchedQuote
        posts = []
        thread.posts.forEach (post) ->
          return if post.isClone or post.isFetchedQuote
          posts.push post
        posts.push thread.OP unless posts.length
        entries.push
          id: thread.ID
          boardID: thread.boardID
          siteID: thread.siteID
          thread: thread
          op: thread.OP
          posts: posts

    entries

  filterPreviewThreadLink: (entry) ->
    {id, boardID, op} = entry
    href = g.SITE.Build.postURL?(boardID, id, id) or g.SITE.Build.threadURL?(boardID, id) or ''
    href = "#p#{id}" unless href

    title = op.info.subject or op.info.comment or op.info.nameBlock or ''
    if !title and op.info.commentHTML?.innerHTML
      title = g.sites[op.siteID]?.Build?.parseComment?(op.info.commentHTML.innerHTML) or ''
    title = title.replace(/\s+/g, ' ').trim()
    title = "#{title[...87]}..." if title.length > 90

    text = "/#{boardID}/#{id}"
    text += " - #{title}" if title

    {href, text}

  sauce: (section) ->
    $.extend section, `<%= readHTML('Sauce.html') %>`
    $('.warning', section).hidden = Conf['Sauce']
    ta = $ 'textarea', section
    $.get 'sauces', Conf['sauces'], (item) ->
      ta.value = item['sauces']
      (ta.hidden = false) # XXX prevent Firefox from adding initialization to undo queue
    $.on ta, 'change', $.cb.value

  advanced: (section) ->
    $.extend section, `<%= readHTML('Advanced.html') %>`
    warning.hidden = Conf[warning.dataset.feature] for warning in $$ '.warning', section

    inputs = $.dict()
    for input in $$ '[name]', section
      inputs[input.name] = input

    $.on inputs['archiveLists'], 'change', ->
      $.set 'lastarchivecheck', 0
      Conf['lastarchivecheck'] = 0
      $.id('lastarchivecheck').textContent = 'never'

    items = $.dict()
    for name, input of inputs when name isnt 'Interval'
      items[name] = Conf[name]
      event = if (
        input.nodeName is 'SELECT' or
        input.type in ['checkbox', 'radio'] or
        (input.nodeName is 'TEXTAREA' and name not of Settings)
      ) then 'change' else 'input'
      $.on input, event, $.cb[if input.type is 'checkbox' then 'checked' else 'value']
      $.on input, event, Settings[name] if name of Settings

    $.get items, (items) ->
      for key, val of items
        input = inputs[key]
        input[if input.type is 'checkbox' then 'checked' else 'value'] = val
        input.hidden = false # XXX prevent Firefox from adding initialization to undo queue
        if key of Settings
          Settings[key].call input
      return

    listImageHost = $.id 'list-fourchanImageHost'
    for textContent in ImageHost.suggestions
      $.add listImageHost, $.el 'option', {textContent}

    interval = inputs['Interval']

    interval.value = Conf['Interval']

    $.on interval, 'change', ThreadUpdater.cb.interval

    itemsArchive = $.dict()
    itemsArchive[name] = Conf[name] for name in ['archives', 'selectedArchives', 'lastarchivecheck']
    $.get itemsArchive, (itemsArchive) ->
      $.extend Conf, itemsArchive
      Redirect.selectArchives()
      Settings.addArchiveTable section

    boardSelect    = $ '#archive-board-select', section
    table          = $ '#archive-table', section
    updateArchives = $ '#update-archives', section

    $.on boardSelect, 'change', ->
      $('tbody > :not([hidden])', table).hidden = true
      $("tbody > .#{@value}", table).hidden = false

    $.on updateArchives, 'click', ->
      Redirect.update ->
        Settings.addArchiveTable section

  addArchiveTable: (section) ->
    $('#lastarchivecheck', section).textContent = if Conf['lastarchivecheck'] is 0
      'never'
    else
      new Date(Conf['lastarchivecheck']).toLocaleString()

    boardSelect = $ '#archive-board-select', section
    table       = $ '#archive-table', section
    tbody       = $ 'tbody', section

    $.rmAll boardSelect
    $.rmAll tbody

    archBoards = $.dict()
    for {uid, name, boards, files, software} in Conf['archives']
      continue unless software in ['fuuka', 'foolfuuka']
      for boardID in boards
        o = archBoards[boardID] or= {
          thread: []
          post:   []
          file:   []
        }
        archive = [uid ? name, name]
        o.thread.push archive
        o.post.push   archive if software is 'foolfuuka'
        o.file.push   archive if boardID in files

    rows = []
    boardOptions = []
    for boardID in Object.keys(archBoards).sort() # Alphabetical order
      row = $.el 'tr',
        className: "board-#{boardID}"
      row.hidden = boardID isnt g.BOARD.ID

      boardOptions.push $.el 'option', {
        textContent: "/#{boardID}/"
        value:       "board-#{boardID}"
        selected:    boardID is g.BOARD.ID
      }

      o = archBoards[boardID]
      $.add row, Settings.addArchiveCell boardID, o, item for item in ['thread', 'post', 'file']
      rows.push row

    if rows.length is 0
      boardSelect.hidden = table.hidden = true
      return

    boardSelect.hidden = table.hidden = false

    unless g.BOARD.ID of archBoards
      rows[0].hidden = false

    $.add boardSelect, boardOptions
    $.add tbody, rows

    for boardID, data of Conf['selectedArchives']
      for type, id of data
        if (select = $ "select[data-boardid='#{boardID}'][data-type='#{type}']", tbody)
          select.value = JSON.stringify id
          select.value = select.firstChild.value unless select.value
    return

  addArchiveCell: (boardID, data, type) ->
    {length} = data[type]
    td = $.el 'td',
      className: 'archive-cell'

    unless length
      td.textContent = '--'
      return td

    options = []
    i = 0
    while i < length
      archive = data[type][i++]
      options.push $.el 'option', {
        value: JSON.stringify archive[0]
        textContent: archive[1]
      }

    $.extend td, `<%= html('<select></select>') %>`
    select = td.firstElementChild
    if not (select.disabled = length is 1)
      # XXX GM can't into datasets
      select.setAttribute 'data-boardid', boardID
      select.setAttribute 'data-type', type
      $.on select, 'change', Settings.saveSelectedArchive
    $.add select, options

    td

  saveSelectedArchive: ->
    $.get 'selectedArchives', Conf['selectedArchives'], ({selectedArchives}) =>
      (selectedArchives[@dataset.boardid] or= $.dict())[@dataset.type] = JSON.parse @value
      $.set 'selectedArchives', selectedArchives
      Conf['selectedArchives'] = selectedArchives
      Redirect.selectArchives()

  boardnav: ->
    Header.generateBoardList @value

  time: ->
    @nextElementSibling.textContent = Time.format @value, new Date()

  timeLocale: ->
    Settings.time.call $('[name=time]', Settings.dialog)

  backlink: ->
    @nextElementSibling.textContent = @value.replace /%(?:id|%)/g, (x) -> ({'%id': '123456789', '%%': '%'})[x]

  fileInfo: ->
    data =
      isReply: true
      file:
        url: "//#{ImageHost.host()}/g/1334437723720.jpg"
        name: 'd9bb2efc98dd0df141a94399ff5880b7.jpg'
        size: '276 KB'
        sizeInBytes: 276 * 1024
        dimensions: '1280x720'
        isImage: true
        isVideo: false
        isSpoiler: true
        tag: 'Loop'
    FileInfo.format @value, data, @nextElementSibling

  favicon: ->
    Favicon.switch()
    Unread.update() if g.VIEW is 'thread' and Conf['Unread Favicon']
    img = @nextElementSibling.children
    f = Favicon
    for icon, i in [f.SFW, f.unreadSFW, f.unreadSFWY, f.NSFW, f.unreadNSFW, f.unreadNSFWY, f.dead, f.unreadDead, f.unreadDeadY]
      $.add @nextElementSibling, $.el('img') unless img[i]
      img[i].src = icon
    return

  setupCSSHighlight: (textarea) ->
    return unless textarea
    wrap = $.el 'div', className: 'css-hl-wrap'
    pre  = $.el 'pre', className: 'css-hl-pre'
    wrap.hidden = true
    textarea.parentNode.insertBefore wrap, textarea
    wrap.appendChild pre
    wrap.appendChild textarea
    update = ->
      pre.innerHTML = Settings.hlCSS textarea.value
      wrap.hidden = false
    textarea._cssHlUpdate = update
    $.on textarea, 'input', update
    $.on textarea, 'scroll', ->
      pre.scrollTop  = textarea.scrollTop
      pre.scrollLeft = textarea.scrollLeft

  'CSS Highlight Theme': ->
    section = $.x 'ancestor::section[1]', @
    wrap = $ '.css-hl-wrap', section
    return unless wrap
    wrap.className = 'css-hl-wrap'
    wrap.classList.add "chl-theme-#{@value}" unless @value is 'auto'

  hlCSS: (raw) ->
    try
      if window.PR?.prettyPrintOne
        escaped = raw.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
        return window.PR.prettyPrintOne escaped, 'css', false
    catch
    Settings.hlCSSFallback raw

  hlCSSFallback: (raw) ->
    esc = (s) -> s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    raw.replace(
      /(\/\*[\s\S]*?\*\/)|("[^"\\]*(?:\\.[^"\\]*)*")|('[^'\\]*(?:\\.[^'\\]*)*')|(@[\w-]+)|(#[0-9a-fA-F]{3,8}(?![0-9a-fA-F\w]))|(-?[0-9]*\.?[0-9]+(?:px|em|rem|vw|vh|vmin|vmax|%|s|ms|deg|fr|ch|ex|pt|cm|mm)?\b)|([\w-]+)(?=\s*:)|([\s\S])/g
      (m, comment, dStr, sStr, atRule, hex, num, prop) ->
        cls = if comment then 'c' else if dStr or sStr then 's' else if atRule then 'a' else if hex then 'l' else if num then 'n' else if prop then 'p' else null
        if cls then "<span class=\"chl-#{cls}\">#{esc m}</span>" else esc m
    )

  togglecss: ->
    section = $.x 'ancestor::section[1]', @
    if (customCSSHome = $('input[name="Custom CSS on Homepage"]', section))
      customCSSHome.disabled = !@checked
    textarea = $('textarea[name=usercss]', section)
    editorFieldset = $('.custom-css-editor', section)
    if textarea.disabled = $.id('apply-css').disabled = !@checked
      CustomCSS.rmStyle()
    else
      CustomCSS.addStyle()
    editorFieldset?.classList.toggle 'custom-css-disabled', !@checked
    $.cb.checked.call @

  refreshGeneratedHighlightStylesEditor: ->
    section = $ '.section-styling', Settings.dialog
    return unless section
    fieldset = $('.generated-highlight-styles', section)
    return unless fieldset

    enabled = !!$('input[name="Generated Highlight Styles"]', section)?.checked
    settings = CustomCSS.generatedHighlightSettings()

    for span in $$ '.generated-highlight-value[data-generated-value]', fieldset
      switch span.dataset.generatedValue
        when 'Highlight Watched Opacity'
          span.textContent = settings.watchedOpacity
        when 'Highlight Your Post Opacity'
          span.textContent = settings.yourPostOpacity
        when 'Highlight Quotes You Opacity'
          span.textContent = settings.quotesYouOpacity

    for input in $$ 'input[type="color"], input[type="range"], .generated-highlight-auto-row input[type="checkbox"]', fieldset
      input.disabled = !enabled

    for colorInput in $$ 'input[type="color"][data-auto-color-for]', fieldset
      autoName = colorInput.dataset.autoColorFor
      autoInput = $("input[name='#{autoName}']", fieldset)
      isAuto = !!autoInput?.checked
      colorInput.disabled = !enabled or isAuto
      autoGroup = $.x 'ancestor::div[contains(@class,"generated-highlight-auto-group")][1]', colorInput
      if isAuto
        $.addClass autoGroup, 'auto-color-hidden' if autoGroup
      else
        $.rmClass autoGroup, 'auto-color-hidden' if autoGroup

    previewStyle = $('.generated-highlight-preview-style', fieldset)
    unless previewStyle
      previewStyle = $.el 'style', className: 'generated-highlight-preview-style'
      $.add fieldset, previewStyle
    previewStyle.textContent = CustomCSS.generatedHighlightPreviewCSS()
    if enabled
      $.rmClass fieldset, 'generated-highlight-disabled'
    else
      $.addClass fieldset, 'generated-highlight-disabled'

  generatedHighlightDefaultValues: ->
    defaults = $.dict()
    for key in CustomCSS.generatedKeys
      defaults[key] = Config[key]
    defaults

  resetGeneratedHighlightStyles: ->
    section = $ '.section-styling', Settings.dialog
    return unless section

    defaults = Settings.generatedHighlightDefaultValues()
    $.set defaults

    for key, val of defaults
      input = $("input[name='#{key}']", section)
      continue unless input
      if input.type is 'checkbox'
        input.checked = !!val
        $.cb.checked.call input
      else
        input.value = val
        $.cb.value.call input
      Settings[key].call input if key of Settings

    Settings.generatedHighlightStylesChanged()

  generatedHighlightStylesChanged: ->
    Settings.refreshGeneratedHighlightStylesEditor()
    CustomCSS.updateGeneratedStyles()

  syncManualHighlightColorFromAuto: (autoName, manualName, derivedName) ->
    section = $ '.section-styling', Settings.dialog
    return unless section
    autoInput = $("input[name='#{autoName}']", section)
    manualInput = $("input[name='#{manualName}']", section)
    return unless autoInput and manualInput
    return if autoInput.checked
    derived = CustomCSS.generatedHighlightSettings()?[derivedName]
    return unless /^#[\da-f]{6}$/i.test derived
    manualInput.value = derived
    $.cb.value.call manualInput

  'Generated Highlight Styles': ->
    Settings.generatedHighlightStylesChanged()

  'Highlight Watched Color': ->
    Settings.generatedHighlightStylesChanged()

  'Highlight Watched Opacity': ->
    Settings.generatedHighlightStylesChanged()

  'Highlight Your Post Color': ->
    Settings.generatedHighlightStylesChanged()

  'Highlight Your Post Opacity': ->
    Settings.generatedHighlightStylesChanged()

  'Highlight Quotes You Color': ->
    Settings.generatedHighlightStylesChanged()

  'Highlight Quotes You Opacity': ->
    Settings.generatedHighlightStylesChanged()

  'Highlight Auto Text Color': ->
    Settings.syncManualHighlightColorFromAuto 'Highlight Auto Text Color', 'Highlight Text Color', 'yourPostTextColor'
    Settings.generatedHighlightStylesChanged()

  'Highlight Text Color': ->
    Settings.generatedHighlightStylesChanged()

  'Highlight Auto Greentext Color': ->
    Settings.syncManualHighlightColorFromAuto 'Highlight Auto Greentext Color', 'Highlight Greentext Color', 'yourPostQuoteColor'
    Settings.generatedHighlightStylesChanged()

  'Highlight Greentext Color': ->
    Settings.generatedHighlightStylesChanged()

  'Highlight Auto Title Color': ->
    Settings.syncManualHighlightColorFromAuto 'Highlight Auto Title Color', 'Highlight Title Color', 'yourPostSubjectColor'
    Settings.generatedHighlightStylesChanged()

  'Highlight Title Color': ->
    Settings.generatedHighlightStylesChanged()

  'Highlight Auto Link Color': ->
    Settings.syncManualHighlightColorFromAuto 'Highlight Auto Link Color', 'Highlight Link Color', 'yourPostLinkColor'
    Settings.generatedHighlightStylesChanged()

  'Highlight Link Color': ->
    Settings.generatedHighlightStylesChanged()

  keybinds: (section) ->
    $.extend section, `<%= readHTML('Keybinds.html') %>`
    $('.warning', section).hidden = Conf['Keybinds']

    tbody  = $ 'tbody', section
    items  = $.dict()
    inputs = $.dict()
    for key, arr of Config.hotkeys
      tr = $.el 'tr',
        `<%= html('<td class="setting-title">${arr[1]}</td><td><input class="field"></td>') %>`
      tr.dataset.name = key
      tr.dataset.settingTitle = arr[1]
      input = $ 'input', tr
      input.name = key
      input.spellcheck = false
      items[key]  = Conf[key]
      inputs[key] = input
      $.on input, 'keydown', Settings.keybind
      $.add tbody, tr

    $.get items, (items) ->
      for key, val of items
        inputs[key].value = val
      return

    if openFiltersMode = $('select[name="Open Filters Mode"]', section)
      $.on openFiltersMode, 'change', $.cb.value
      $.get 'Open Filters Mode', Conf['Open Filters Mode'], (item) ->
        mode = item['Open Filters Mode']
        mode = 'remember' unless mode in ['remember', 'simple', 'advanced', 'filtered']
        openFiltersMode.value = mode
      openFiltersMode.hidden = false

  keybind: (e) ->
    return if e.keyCode is 9 # tab
    e.preventDefault()
    e.stopPropagation()
    return unless (key = Keybinds.keyCode e)?
    @value = key
    $.cb.value.call @
