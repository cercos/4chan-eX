ScrollMarkers =
  init: ->
    return unless g.VIEW is 'thread' and Conf['Scrollbar Markers']

    @container = $.el 'div', id: 'scroll-markers'
    @container.hidden = true

    for key in ['Scrollbar Mark Own Posts', 'Scrollbar Mark Quotes You', 'Scrollbar Mark Ghost Posts']
      $.sync key, (val, k) ->
        Conf[k] = val
        ScrollMarkers.refreshDeferred()

    Callbacks.Thread.push
      name: 'Scroll Markers'
      cb:   @node

  node: ->
    ScrollMarkers.thread = @
    $.add d.body, ScrollMarkers.container
    ScrollMarkers.container.hidden = false

    $.on d, '4chanXInitFinished',           ScrollMarkers.refreshDeferred
    $.on d, 'PostsInserted',                ScrollMarkers.refreshDeferred
    $.on d, 'ThreadUpdate',                 ScrollMarkers.refreshDeferred
    $.on d, 'YouMarkChanged',               ScrollMarkers.refreshDeferred
    $.on window, 'resize',                  ScrollMarkers.refreshDeferred
    $.on window, 'load',                    ScrollMarkers.refreshDeferred

    ScrollMarkers.refreshDeferred()

  refreshDeferred: $.debounce 150, ->
    ScrollMarkers.refresh()

  refresh: ->
    return unless ScrollMarkers.thread and ScrollMarkers.container.parentNode

    container = ScrollMarkers.container
    docHeight = d.documentElement.scrollHeight or d.body.scrollHeight or 0
    return unless docHeight > 0

    frag      = $.frag()
    showOwn   = Conf['Highlight Own Posts']         and Conf['Scrollbar Mark Own Posts']
    showYou   = Conf['Highlight Posts Quoting You'] and Conf['Scrollbar Mark Quotes You']
    showGhost = Conf['Highlight Ghost Posts']       and Conf['Scrollbar Mark Ghost Posts']

    ScrollMarkers.thread.posts.forEach (post) ->
      return if post.isHidden or post.isClone or post.isFetchedQuote
      isGhost = !!post.isGhostPost
      root = post.nodes.root
      return unless root and root.offsetParent isnt null and root.getClientRects().length

      isOwn = showOwn and root.classList.contains('yourPost')
      isYou = showYou and root.classList.contains('quotesYou')
      showThisGhost = showGhost and isGhost
      return unless isOwn or isYou or showThisGhost

      rect = root.getBoundingClientRect()
      topInDoc = rect.top + window.scrollY
      topPct = (topInDoc / docHeight) * 100
      heightPct = Math.max((rect.height / docHeight) * 100, 0.15)

      if isOwn
        marker = $.el 'div',
          className: 'scroll-marker scroll-marker-own'
          style: "top:#{topPct}%;height:#{heightPct}%"
        ScrollMarkers.bind marker, post
        $.add frag, marker
      if isYou
        marker = $.el 'div',
          className: 'scroll-marker scroll-marker-you'
          style: "top:#{topPct}%;height:#{heightPct}%"
        ScrollMarkers.bind marker, post
        $.add frag, marker
      if showThisGhost
        marker = $.el 'div',
          className: 'scroll-marker scroll-marker-ghost'
          style: "top:#{topPct}%;height:#{heightPct}%"
        ScrollMarkers.bind marker, post
        $.add frag, marker
      return

    container.textContent = ''
    $.add container, frag
    return

  bind: (marker, post) ->
    marker.title = "Post No.#{post.ID}"
    $.on marker, 'mouseenter', ->
      ScrollMarkers.highlightPost post
    $.on marker, 'mouseleave', ->
      ScrollMarkers.unhighlightPost post
    $.on marker, 'click', (e) ->
      e.preventDefault()
      ScrollMarkers.jumpTo post

  highlightPost: (post) ->
    return unless post?.nodes?.root?.isConnected
    $.addClass post.nodes.root, 'qphl'

  unhighlightPost: (post) ->
    return unless post?.nodes?.root
    $.rmClass post.nodes.root, 'qphl'

  jumpTo: (post) ->
    return unless post?.nodes?.root?.isConnected
    Header.scrollTo post.nodes.root
    $.addClass post.nodes.root, 'qphl'
    clearTimeout ScrollMarkers.flashTimer
    ScrollMarkers.flashPost = post
    ScrollMarkers.flashTimer = setTimeout (->
      $.rmClass ScrollMarkers.flashPost.nodes.root, 'qphl' if ScrollMarkers.flashPost?.nodes?.root
      ScrollMarkers.flashPost = null
    ), 1500
