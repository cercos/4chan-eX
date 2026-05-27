Embedding =
  init: ->
    return unless g.VIEW in ['index', 'thread', 'archive'] and Conf['Linkify'] and (Conf['Embedding'] or Conf['Link Title'] or Conf['Cover Preview'])
    @types = $.dict()
    @types[type.key] = type for type in @ordered_types

    if Conf['Embedding'] and g.VIEW isnt 'archive'
      @dialog = UI.dialog 'embedding',
        `<%= readHTML('Embed.html') %>`
      @media = $ '#media-embed', @dialog
      $.one d, '4chanXInitFinished', @ready
      $.on  d, 'IndexRefreshInternal', ->
        g.posts.forEach (post) ->
          for post in [post, post.clones...]
            for embed in post.nodes.embedlinks
              Embedding.cb.catalogRemove.call embed
          return
    if Conf['Link Title']
      $.on d, '4chanXInitFinished PostsInserted', ->
        for key, service of Embedding.types when service.title?.batchSize
          Embedding.flushTitles service.title
        return

  events: (post) ->
    return if g.VIEW is 'archive'
    if Conf['Embedding']
      i = 0
      items = post.nodes.embedlinks = $$ '.embedder', post.nodes.comment
      while el = items[i++]
        $.on el, 'click', Embedding.cb.click
        Embedding.cb.toggle.call el if $.hasClass el, 'embedded'
    if Conf['Cover Preview']
      i = 0
      items = $$ '.linkify', post.nodes.comment
      while el = items[i++]
        if (data = Embedding.services el)
          Embedding.preview data
      return

  process: (link, post) ->
    return if $.x 'ancestor::pre', link
    if data = Embedding.services link
      Embedding.convertToXcancel link, data.uid if data.key is 'Twitter' and Conf['Convert X to xcancel']
      return unless Conf['Embedding'] or Conf['Link Title'] or Conf['Cover Preview']
      data.post = post
      Embedding.embed data if Conf['Embedding'] and g.VIEW isnt 'archive'
      Embedding.title data if Conf['Link Title']
      Embedding.preview data if Conf['Cover Preview'] and g.VIEW isnt 'archive'

  convertToXcancel: (link, uid) ->
    newHref = "https://xcancel.com/#{uid}"
    return if link.href is newHref
    oldText = link.textContent
    link.href = newHref
    if /^\w+:\/\/(?:www\.|mobile\.)?(?:twitter\.com|x\.com)/i.test oldText
      link.textContent = oldText.replace /^(\w+:\/\/)(?:www\.|mobile\.)?(?:twitter\.com|x\.com)/i, '$1xcancel.com'

  services: (link) ->
    {href} = link
    for type in Embedding.ordered_types when (match = type.regExp.exec href)
      return {key: type.key, uid: match[1], options: match[2], link}
    return

  embed: (data) ->
    {key, uid, options, link, post} = data
    {href} = link

    $.addClass link, key.toLowerCase()

    embed = $.el 'a',
      className:   'embedder'
      href:        'javascript:;'
    ,
      `<%= html('(<span>un</span>embed)') %>`

    embed.dataset[name] = value for name, value of {key, uid, options, href}

    $.on embed, 'click', Embedding.cb.click
    $.after link, [$.tn(' '), embed]
    post.nodes.embedlinks.push embed

    if Conf['Auto-embed'] and !Conf['Floating Embeds'] and !post.isFetchedQuote
      if $.hasClass(doc, 'catalog-mode')
        $.addClass embed, 'embed-removed'
      else
        Embedding.cb.toggle.call embed

  ready: ->
    return if !Main.isThisPageLegit()
    $.addClass Embedding.dialog, 'empty'
    $.on $('.close', Embedding.dialog), 'click',     Embedding.closeFloat
    $.on $('.move',  Embedding.dialog), 'mousedown', Embedding.dragEmbed
    $.on $('.jump',  Embedding.dialog), 'click', ->
      (Header.scrollTo Embedding.lastEmbed if doc.contains Embedding.lastEmbed)
    $.add d.body, Embedding.dialog

  closeFloat: ->
    delete Embedding.lastEmbed
    $.addClass Embedding.dialog, 'empty'
    $.replace Embedding.media.firstChild, $.el 'div'

  dragEmbed: ->
    # only webkit can handle a blocking div
    {style} = Embedding.media
    if Embedding.dragEmbed.mouseup
      $.off d, 'mouseup', Embedding.dragEmbed
      Embedding.dragEmbed.mouseup = false
      style.pointerEvents = ''
      return
    $.on d, 'mouseup', Embedding.dragEmbed
    Embedding.dragEmbed.mouseup = true
    style.pointerEvents = 'none'

  title: (data) ->
    {key, uid, options, link, post} = data
    return if not (service = Embedding.types[key].title)
    $.addClass link, key.toLowerCase()
    if service.batchSize
      (service.queue or= []).push data
      if service.queue.length >= service.batchSize
        Embedding.flushTitles service
    else
      CrossOrigin.cache service.api(uid), (-> Embedding.cb.title @, data)

  flushTitles: (service) ->
    {queue} = service
    return unless queue?.length
    service.queue = []
    cb = ->
      Embedding.cb.title @, data for data in queue
      return
    CrossOrigin.cache service.api(data.uid for data in queue), cb

  preview: (data) ->
    {key, uid, link} = data
    return if not (service = Embedding.types[key].preview)
    $.on link, 'mouseover', (e) ->
      src = service.url uid
      {height} = service
      el = $.el 'img',
        src: src
        id: 'ihover'
      $.add Header.hover, el
      UI.hover
        root: link
        el: el
        latestEvent: e
        endEvents: 'mouseout click'
        height: height

  cb:
    click: (e) ->
      e.preventDefault()
      if not $.hasClass(@, 'embedded') and (Conf['Floating Embeds'] or $.hasClass(doc, 'catalog-mode'))
        return if not (div = Embedding.media.firstChild)
        $.replace div, Embedding.cb.embed @
        Embedding.lastEmbed = Get.postFromNode(@).nodes.root
        $.rmClass Embedding.dialog, 'empty'
      else
        Embedding.cb.toggle.call @

    toggle: ->
      if $.hasClass @, "embedded"
        $.rm @nextElementSibling
      else
        $.after @, Embedding.cb.embed @
      $.toggleClass @, 'embedded'

    embed: (a) ->
      # We create an element to embed
      container = $.el 'div', {className: 'media-embed'}
      $.add container, el = (type = Embedding.types[a.dataset.key]).el a

      # Set style values.
      el.style.cssText = if type.style?
        type.style
      else
        'border: none; width: 640px; height: 360px;'

      return container

    catalogRemove: ->
      isCatalog = $.hasClass(doc, 'catalog-mode')
      if (isCatalog and $.hasClass(@, 'embedded')) or (!isCatalog and $.hasClass(@, 'embed-removed'))
        Embedding.cb.toggle.call @
        $.toggleClass @, 'embed-removed'

    title: (req, data) ->
      {key, uid, options, link, post} = data
      service = Embedding.types[key].title

      {status} = req
      if status in [200, 304] and service.status
        status = service.status(req.response)[0]

      return unless status

      text = "[#{key}] #{switch status
        when 200, 304
          text = service.text req.response, uid
          if typeof text is 'string'
            text
          else
            text = link.textContent
        when 404
          "Not Found"
        when 403, 401
          "Forbidden or Private"
        else
          "#{status}'d"
      }"

      link.dataset.original = link.textContent
      link.textContent = text
      for post2 in post.clones
        for link2 in $$ 'a.linkify', post2.nodes.comment when link2.href is link.href
          link2.dataset.original ?= link2.textContent
          link2.textContent = text
      return

  ordered_types: [
      key: 'audio'
      regExp: /^[^?#]+\.(?:mp3|m4a|oga|wav|flac)(?:[?#]|$)/i
      style: ''
      el: (a) ->
        $.el 'audio',
          controls:    true
          preload:     'auto'
          src:         a.dataset.href
    ,
      key: 'image'
      regExp: /^[^?#]+\.(?:gif|png|jpg|jpeg|bmp|webp)(?::\w+)?(?:[?#]|$)/i
      style: ''
      el: (a) ->
        $.el 'div', `<%= html('<a target="_blank" href="${a.dataset.href}"><img src="${a.dataset.href}" style="max-width: 80vw; max-height: 80vh;"></a>') %>`
    ,
      key: 'video'
      regExp: /^[^?#]+\.(?:og[gv]|webm|mp4)(?:[?#]|$)/i
      style: 'max-width: 80vw; max-height: 80vh;'
      el: (a) ->
        el = $.el 'video',
          hidden:   true
          controls: true
          preload:  'auto'
          src:      a.dataset.href
          loop:     ImageHost.test a.dataset.href.split('/')[2]
        $.on el, 'loadedmetadata', ->
          if el.videoHeight is 0 and el.parentNode
            $.replace el, Embedding.types.audio.el(a)
          else
            el.hidden = false
        el
    ,
      key: 'PeerTube'
      regExp: /^(\w+:\/\/[^\/]+\/videos\/watch\/\w{8}-\w{4}-\w{4}-\w{4}-\w{12})(.*)/
      el: (a) ->
        options = if (start = a.dataset.options.match /[?&](start=\w+)/) then "?#{start[1]}" else ''
        el = $.el 'iframe',
          src: a.dataset.uid.replace('/videos/watch/', '/videos/embed/') + options
        el.setAttribute "allowfullscreen", "true"
        el
    ,
      key: 'BitChute'
      regExp:  /^\w+:\/\/(?:www\.)?bitchute\.com\/video\/([\w\-]+)/
      el: (a) ->
        el = $.el 'iframe',
          src: "https://www.bitchute.com/embed/#{a.dataset.uid}/"
        el.setAttribute "allowfullscreen", "true"
        el
    ,
      key: 'Bilibili'
      regExp: /^\w+:\/\/(?:www\.|m\.)?bilibili\.com\/video\/(BV[A-Za-z0-9]+|av\d+)/i
      el: (a) ->
        uid = a.dataset.uid
        param = if /^av/i.test(uid) then "aid=#{uid.replace(/^av/i, '')}" else "bvid=#{uid}"
        el = $.el 'iframe',
          src: "https://player.bilibili.com/player.html?#{param}&high_quality=1&autoplay=0"
        el.setAttribute "allowfullscreen", "true"
        el
    ,
      key: 'Clyp'
      regExp: /^\w+:\/\/(?:www\.)?clyp\.it\/(\w{8})/
      style: 'border: 0; width: 640px; height: 160px;'
      el: (a) ->
        $.el 'iframe',
          src: "https://clyp.it/#{a.dataset.uid}/widget"
      title:
        api: (uid) -> "https://api.clyp.it/oembed?url=https://clyp.it/#{uid}"
        text: (_) -> _.title
    ,
      key: 'Dailymotion'
      regExp:  /^\w+:\/\/(?:(?:www\.)?dailymotion\.com\/(?:embed\/)?video|dai\.ly)\/([A-Za-z0-9]+)[^?]*(.*)/
      el: (a) ->
        options = if (start = a.dataset.options.match /[?&](start=\d+)/) then "?#{start[1]}" else ''
        el = $.el 'iframe',
          src: "//www.dailymotion.com/embed/video/#{a.dataset.uid}#{options}"
        el.setAttribute "allowfullscreen", "true"
        el
      title:
        api: (uid) -> "https://api.dailymotion.com/video/#{uid}"
        text: (_) -> _.title
      preview:
        url: (uid) -> "https://www.dailymotion.com/thumbnail/video/#{uid}"
        height: 240
    ,
      key: 'Gfycat'
      regExp: /^\w+:\/\/(?:www\.)?gfycat\.com\/(?:iframe\/)?(\w+)/
      el: (a) ->
        el = $.el 'iframe',
          src: "//gfycat.com/ifr/#{a.dataset.uid}"
        el.setAttribute "allowfullscreen", "true"
        el
    ,
      key: 'Gist'
      regExp: /^\w+:\/\/gist\.github\.com\/[\w\-]+\/(\w+)/
      style: ''
      el: do ->
        counter = 0
        (a) ->
          el = $.el 'pre',
            hidden: true
            id: "gist-embed-#{counter++}"
          CrossOrigin.cache "https://api.github.com/gists/#{a.dataset.uid}", ->
            el.textContent = Object.values(@response.files)[0].content
            el.className = 'prettyprint'
            $.global ->
              window.prettyPrint? (() ->), document.getElementById(document.currentScript.dataset.id).parentNode
            , id: el.id
            el.hidden = false
          el
      title:
        api: (uid) -> "https://api.github.com/gists/#{uid}"
        text: ({files}) ->
          return file for file of files when files.hasOwnProperty file
    ,
      key: 'InstallGentoo'
      regExp: /^\w+:\/\/paste\.installgentoo\.com\/view\/(?:raw\/|download\/|embed\/)?(\w+)/
      el: (a) ->
        $.el 'iframe',
          src: "https://paste.installgentoo.com/view/embed/#{a.dataset.uid}"
    ,
      key: 'LiveLeak'
      regExp: /^\w+:\/\/(?:\w+\.)?liveleak\.com\/.*\?.*[tif]=(\w+)/
      el: (a) ->
        el = $.el 'iframe',
          src: "https://www.liveleak.com/e/#{a.dataset.uid}",
        el.setAttribute "allowfullscreen", "true"
        el
    ,
      key: 'Loopvid'
      regExp: /^\w+:\/\/(?:www\.)?loopvid.appspot.com\/#?((?:pf|kd|lv|gd|gh|db|dx|nn|cp|wu|ig|ky|mf|m2|pc|1c|pi|ni|wl|ko|mm|ic|gc)\/[\w\-\/]+(?:,[\w\-\/]+)*|fc\/\w+\/\d+|https?:\/\/.+)/
      style: 'max-width: 80vw; max-height: 80vh;'
      el: (a) ->
        el = $.el 'video',
          controls: true
          preload:  'auto'
          loop:     true
        if /^http/.test a.dataset.uid
          $.add el, $.el 'source', src: a.dataset.uid
          return el
        [_, host, names] = a.dataset.uid.match /(\w+)\/(.*)/
        types = switch host
          when 'gd', 'wu', 'fc' then ['']
          when 'gc' then ['giant', 'fat', 'zippy']
          else ['.webm', '.mp4']
        for name in names.split ','
          for type in types
            base = "#{name}#{type}"
            urls = switch host
              # list from src/common.py at http://loopvid.appspot.com/source.html
              when 'pf' then ["https://kastden.org/_loopvid_media/pf/#{base}", "https://web.archive.org/web/2/http://a.pomf.se/#{base}"]
              when 'kd' then ["https://kastden.org/loopvid/#{base}"]
              when 'lv' then ["https://lv.kastden.org/#{base}"]
              when 'gd' then ["https://docs.google.com/uc?export=download&id=#{base}"]
              when 'gh' then ["https://googledrive.com/host/#{base}"]
              when 'db' then ["https://dl.dropboxusercontent.com/u/#{base}"]
              when 'dx' then ["https://dl.dropboxusercontent.com/#{base}"]
              when 'nn' then ["https://kastden.org/_loopvid_media/nn/#{base}"]
              when 'cp' then ["https://copy.com/#{base}"]
              when 'wu' then ["http://webmup.com/#{base}/vid.webm"]
              when 'ig' then ["https://i.imgur.com/#{base}"]
              when 'ky' then ["https://kastden.org/_loopvid_media/ky/#{base}"]
              when 'mf' then ["https://kastden.org/_loopvid_media/mf/#{base}", "https://web.archive.org/web/2/https://d.maxfile.ro/#{base}"]
              when 'm2' then ["https://kastden.org/_loopvid_media/m2/#{base}"]
              when 'pc' then ["https://kastden.org/_loopvid_media/pc/#{base}", "https://web.archive.org/web/2/http://a.pomf.cat/#{base}"]
              when '1c' then ["http://b.1339.cf/#{base}"]
              when 'pi' then ["https://kastden.org/_loopvid_media/pi/#{base}", "https://web.archive.org/web/2/https://u.pomf.is/#{base}"]
              when 'ni' then ["https://kastden.org/_loopvid_media/ni/#{base}", "https://web.archive.org/web/2/https://u.nya.is/#{base}"]
              when 'wl' then ["http://webm.land/media/#{base}"]
              when 'ko' then ["https://kordy.kastden.org/loopvid/#{base}"]
              when 'mm' then ["https://kastden.org/_loopvid_media/mm/#{base}", "https://web.archive.org/web/2/https://my.mixtape.moe/#{base}"]
              when 'ic' then ["https://media.8ch.net/file_store/#{base}"]
              when 'fc' then ["//#{ImageHost.host()}/#{base}.webm"]
              when 'gc' then ["https://#{type}.gfycat.com/#{name}.webm"]

            for url in urls
              $.add el, $.el 'source', src: url
        el
    ,
      key: 'Odysee'
      regExp: /^\w+:\/\/(?:www\.)?odysee\.com\/(?:\$\/embed\/)?(@?[^?#]+)/
      el: (a) ->
        el = $.el 'iframe',
          src: "https://odysee.com/$/embed/#{a.dataset.uid}"
        el.setAttribute "allowfullscreen", "true"
        el
    ,
      key: 'Openings.moe'
      regExp: /^\w+:\/\/openings.moe\/\?video=([^.&=]+)/
      style: 'width: 1280px; height: 720px; max-width: 80vw; max-height: 80vh;'
      el: (a) ->
        el = $.el 'iframe',
          src: "https://openings.moe/?video=#{a.dataset.uid}",
        el.setAttribute "allowfullscreen", "true"
        el
    ,
      key: 'Pastebin'
      regExp: /^\w+:\/\/(?:\w+\.)?pastebin\.com\/(?!u\/)(?:[\w.]+(?:\/|\?i\=))?(\w+)/
      el: (a) ->
        div = $.el 'iframe',
          src: "//pastebin.com/embed_iframe.php?i=#{a.dataset.uid}"
    ,
      key: 'Rumble'
      regExp: /^\w+:\/\/(?:www\.)?rumble\.com\/(?:embed\/)?(v[A-Za-z0-9]+)(?:[-./?#]|$)/i
      el: (a) ->
        el = $.el 'iframe',
          src: "https://rumble.com/embed/#{a.dataset.uid}/?pub=4"
        el.setAttribute "allowfullscreen", "true"
        el
    ,
      key: 'SoundCloud'
      regExp: /^\w+:\/\/(?:www\.)?(?:soundcloud\.com\/|snd\.sc\/)([\w\-\/]+)/
      style: 'border: 0; width: 500px; height: 400px;'
      el: (a) ->
        $.el 'iframe',
          src: "https://w.soundcloud.com/player/?visual=true&show_comments=false&url=https%3A%2F%2Fsoundcloud.com%2F#{encodeURIComponent a.dataset.uid}"
      title:
        api: (uid) -> "#{location.protocol}//soundcloud.com/oembed?format=json&url=https%3A%2F%2Fsoundcloud.com%2F#{encodeURIComponent uid}"
        text: (_) -> _.title
    ,
      key: 'Spotify'
      regExp: /^\w+:\/\/open\.spotify\.com\/(?:embed\/)?((?:track|album|playlist|episode|show|artist)\/[A-Za-z0-9]+)/
      style: 'border: 0; width: 500px; height: 380px;'
      el: (a) ->
        $.el 'iframe',
          src: "https://open.spotify.com/embed/#{a.dataset.uid}"
    ,
      key: 'StrawPoll'
      regExp: /^\w+:\/\/(?:www\.)?strawpoll\.me\/(?:embed_\d+\/)?(\d+(?:\/r)?)/
      style: 'border: 0; width: 600px; height: 406px;'
      el: (a) ->
        $.el 'iframe',
          src: "https://www.strawpoll.me/embed_1/#{a.dataset.uid}"
    ,
      key: 'Streamable'
      regExp: /^\w+:\/\/(?:www\.)?streamable\.com\/(\w+)/
      el: (a) ->
        el = $.el 'iframe',
          src: "https://streamable.com/o/#{a.dataset.uid}"
        el.setAttribute "allowfullscreen", "true"
        el
      title:
        api: (uid) -> "https://api.streamable.com/oembed?url=https://streamable.com/#{uid}"
        text: (_) -> _.title
    ,
      key: 'TikTok'
      regExp: /^\w+:\/\/(?:www\.|m\.)?tiktok\.com\/@[^\/]+\/video\/(\d+)/
      style: 'border: 0; width: 340px; height: 700px;'
      el: (a) ->
        el = $.el 'iframe',
          src: "https://www.tiktok.com/embed/v2/#{a.dataset.uid}"
        el.setAttribute "allowfullscreen", "true"
        el
    ,
      key: 'TwitchTV'
      regExp: /^\w+:\/\/(?:www\.|secure\.|clips\.|m\.)?twitch\.tv\/(\w[^#\&\?]*)/
      el: (a) ->
        m = a.dataset.href.match /^\w+:\/\/(?:(clips\.)|\w+\.)?twitch\.tv\/(?:\w+\/)?(clip\/)?(\w[^#\&\?]*)/;
        if m[1] or m[2]
          url = "//clips.twitch.tv/embed?clip=#{m[3]}&parent=#{location.hostname}"
        else
          m = a.dataset.uid.match /(\w+)(?:\/(?:v\/)?(\d+))?/
          url = "//player.twitch.tv/?#{if m[2] then "video=v#{m[2]}" else "channel=#{m[1]}"}&autoplay=false&parent=#{location.hostname}"
          if (time = a.dataset.href.match /\bt=(\w+)/)
            url += "&time=#{time[1]}"
        el = $.el 'iframe',
          src: url
        el.setAttribute "allowfullscreen", "true"
        el
    ,
      key: 'Twitter'
      regExp: /^\w+:\/\/(?:www\.|mobile\.)?(?:twitter\.com|x\.com|xcancel\.com)\/(\w+\/status\/\d+)/
      style: 'border: 1px solid var(--reply-border-color, rgba(128,128,128,0.4)); width: 550px; max-height: 80vh; overflow: auto; resize: both; padding: 12px; box-sizing: border-box; display: flex; flex-direction: column; gap: 8px;'
      el: (a) ->
        container = $.el 'div', className: 'twitter-embed'
        container.textContent = 'Loading tweet…'

        renderTweet = (tweet) ->
          container.textContent = ''

          header = $.el 'div'
          header.style.cssText = 'display: flex; align-items: center; gap: 8px;'
          if tweet.author?.avatar_url
            avatar = $.el 'img', src: tweet.author.avatar_url, alt: ''
            avatar.style.cssText = 'width: 40px; height: 40px; border-radius: 50%; flex-shrink: 0;'
            $.add header, avatar
          meta = $.el 'div'
          meta.style.cssText = 'min-width: 0; flex: 1;'
          name = $.el 'div', textContent: (tweet.author?.name or '')
          name.style.fontWeight = 'bold'
          handle = $.el 'a',
            href: "https://twitter.com/#{tweet.author?.screen_name or ''}"
            textContent: "@#{tweet.author?.screen_name or ''}"
            target: '_blank'
            rel: 'noreferrer'
          handle.style.cssText = 'opacity: 0.7; font-size: 0.9em;'
          $.add meta, [name, handle]
          $.add header, meta
          $.add container, header

          if tweet.text
            text = $.el 'div'
            text.style.cssText = 'white-space: pre-wrap; word-wrap: break-word;'
            re = /(https?:\/\/\S+)/g
            lastIndex = 0
            while (m = re.exec(tweet.text))
              if m.index > lastIndex
                $.add text, $.tn(tweet.text.substring(lastIndex, m.index))
              link = $.el 'a',
                href: m[1]
                textContent: m[1]
                target: '_blank'
                rel: 'noreferrer'
              $.add text, link
              lastIndex = re.lastIndex
            if lastIndex < tweet.text.length
              $.add text, $.tn(tweet.text.substring(lastIndex))
            $.add container, text

          if tweet.media?.videos?.length
            for video in tweet.media.videos
              v = $.el 'video',
                controls: true
                preload: 'metadata'
              v.style.cssText = 'max-width: 100%; max-height: 60vh;'
              v.poster = video.thumbnail_url if video.thumbnail_url
              source = $.el 'source',
                src: video.url
                type: video.content_type or 'video/mp4'
              $.add v, source
              $.add container, v
          else if tweet.media?.photos?.length
            photos = tweet.media.photos
            grid = $.el 'div'
            cols = if photos.length > 1 then 'repeat(2, 1fr)' else '1fr'
            grid.style.cssText = "display: grid; gap: 4px; grid-template-columns: #{cols};"
            for photo in photos
              link = $.el 'a', href: photo.url, target: '_blank', rel: 'noreferrer'
              img = $.el 'img', src: photo.url, alt: ''
              img.style.cssText = 'width: 100%; height: auto; max-height: 60vh; object-fit: contain;'
              $.add link, img
              $.add grid, link
            $.add container, grid

          stats = $.el 'div'
          stats.style.cssText = 'display: flex; gap: 12px; opacity: 0.7; font-size: 0.85em;'
          stats.textContent = "#{tweet.replies or 0} replies · #{tweet.retweets or 0} retweets · #{tweet.likes or 0} likes"
          $.add container, stats
          return

        $.ajax "https://api.fxtwitter.com/#{a.dataset.uid}",
          responseType: 'json'
          onloadend: ->
            tweet = @response?.tweet
            if tweet
              renderTweet tweet
            else
              container.textContent = 'Failed to load tweet.'
        container
    ,
      key: 'VidLii'
      regExp:  /^\w+:\/\/(?:www\.)?vidlii\.com\/watch\?v=(\w{11})/
      style: 'border: none; width: 640px; height: 392px;'
      el: (a) ->
        el = $.el 'iframe',
          src: "https://www.vidlii.com/embed?v=#{a.dataset.uid}&a=0"
        el.setAttribute "allowfullscreen", "true"
        el
    ,
      key: 'Vimeo'
      regExp:  /^\w+:\/\/(?:www\.)?vimeo\.com\/(\d+)/
      el: (a) ->
        el = $.el 'iframe',
          src: "//player.vimeo.com/video/#{a.dataset.uid}?wmode=opaque"
        el.setAttribute "allowfullscreen", "true"
        el
      title:
        api: (uid) -> "https://vimeo.com/api/oembed.json?url=https://vimeo.com/#{uid}"
        text: (_) -> _.title
    ,
      key: 'Vine'
      regExp: /^\w+:\/\/(?:www\.)?vine\.co\/v\/(\w+)/
      style: 'border: none; width: 500px; height: 500px;'
      el: (a) ->
        $.el 'iframe',
          src: "https://vine.co/v/#{a.dataset.uid}/card"
    ,
      key: 'Vocaroo'
      regExp: /^\w+:\/\/(?:(?:www\.|old\.)?vocaroo\.com|voca\.ro)\/((?:i\/)?\w+)/
      style: ''
      el: (a) ->
        el = $.el 'iframe'
        el.width = 300
        el.height = 60
        el.setAttribute('frameborder', 0)
        el.src = "https://vocaroo.com/embed/#{a.dataset.uid.replace(/^i\//, '')}?autoplay=0"
        el
    ,
      key: 'YouTube'
      regExp: /^\w+:\/\/(?:youtu.be\/|[\w.]*youtube[\w.]*\/.*(?:v=|\bembed\/|\bv\/|live\/|shorts\/))([\w\-]{11})(.*)/
      el: (a) ->
        start = a.dataset.options.match /\b(?:star)?t\=(\w+)/
        start = start[1] if start
        if start and !/^\d+$/.test start
          start += ' 0h0m0s'
          start = 3600 * start.match(/(\d+)h/)[1] + 60 * start.match(/(\d+)m/)[1] + 1 * start.match(/(\d+)s/)[1]
        el = $.el 'iframe',
          src: "//www.youtube.com/embed/#{a.dataset.uid}?rel=0&wmode=opaque#{if start then '&start=' + start else ''}"
        el.setAttribute "allowfullscreen", "true"
        el
      title:
        api: (uid) -> "https://www.youtube.com/oembed?url=https%3A//www.youtube.com/watch%3Fv%3D#{uid}&format=json"
        text: (_) -> _.title
        status: (_) ->
          if _.error
            m = _.error.match(/^(\d*)\s*(.*)/)
            [+m[1], m[2]]
          else
            [200, 'OK']
      preview:
        url: (uid) -> "https://img.youtube.com/vi/#{uid}/0.jpg"
        height: 360
  ]
