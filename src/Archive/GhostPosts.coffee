GhostPosts =
  init: ->
    if Conf['Highlight Ghost Posts']
      $.addClass doc, 'highlight-ghost'
    $.sync 'Highlight Ghost Posts', (enabled) ->
      Conf['Highlight Ghost Posts'] = enabled
      doc.classList.toggle 'highlight-ghost', enabled

    return unless g.VIEW is 'thread' and Conf['Fetch Ghost Posts']
    return unless Conf['Resurrect Quotes']
    Callbacks.Thread.push
      name: 'Ghost Posts'
      cb:   @node

  node: ->
    GhostPosts.thread = @
    GhostPosts.fetched = false
    $.one d, '4chanXInitFinished', GhostPosts.start
    $.on d, 'ThreadUpdate', GhostPosts.onThreadUpdate

  onThreadUpdate: (e) ->
    return if e.detail[404]
    return unless e.detail.deletedPosts?.length
    GhostPosts.fetched = false
    GhostPosts.start()

  start: ->
    return if GhostPosts.fetched
    GhostPosts.fetched = true
    {board, ID: threadID} = GhostPosts.thread
    boardID = board.ID

    archive = Redirect.data.thread[boardID]
    return unless archive and archive.software is 'foolfuuka'

    url = "#{Redirect.protocol archive}#{archive.domain}/_/api/chan/thread/?board=#{boardID}&num=#{threadID}"
    return unless Redirect.securityCheck url

    CrossOrigin.cache url, ->
      GhostPosts.handle @, url, archive

  handle: (req, url, archive) ->
    {status, response} = req
    return unless status in [200, 304] and response
    return unless GhostPosts.thread

    {board, ID: threadID} = GhostPosts.thread
    boardID = board.ID
    threadObj = response[threadID] or response[String(threadID)]
    return unless threadObj

    knownIDs = $.dict()
    GhostPosts.thread.posts.forEach (post) ->
      knownIDs[post.ID] = true

    archivePosts = []
    if threadObj.posts
      for postIDStr, postData of threadObj.posts
        postID = +postIDStr
        continue unless postID
        continue if knownIDs[postID]
        archivePosts.push {postID, postData}

    return unless archivePosts.length
    archivePosts.sort (a, b) -> a.postID - b.postID

    built = []
    for {postID, postData} in archivePosts
      try
        post = Fetcher.buildArchivedPost postData, url, archive, boardID, postID, {isFetchedQuote: false, isGhostPost: true}
        if post
          $.addClass post.nodes.root, 'ghost-post'
          built.push post
      catch err
        c.error? 'GhostPosts build failed for', postID, err

    return unless built.length

    Main.callbackNodes 'Post', built

    threadRoot = GhostPosts.thread.OP.nodes.root.parentNode
    return unless threadRoot

    livePosts = []
    GhostPosts.thread.posts.forEach (post) ->
      return if post.isGhostPost
      livePosts.push post

    for post in built
      next = null
      for live in livePosts when live.ID > post.ID
        next = live
        break
      if next?.nodes.root.parentNode is threadRoot
        $.before next.nodes.root, post.nodes.root
      else
        $.add threadRoot, post.nodes.root
      livePosts.push post
      livePosts.sort (a, b) -> a.ID - b.ID

    $.event 'PostsInserted', null, threadRoot
    new Notice 'info', "Loaded #{built.length} ghost post#{if built.length is 1 then '' else 's'} from #{archive.name}.", 8
