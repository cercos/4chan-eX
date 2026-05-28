CustomCSS =
  generatedKeys: [
    'Generated Highlight Styles'
    'Highlight Watched Color'
    'Highlight Watched Opacity'
    'Highlight Your Post Color'
    'Highlight Your Post Opacity'
    'Highlight Quotes You Color'
    'Highlight Quotes You Opacity'
    'Highlight Ghost Post Color'
    'Highlight Ghost Post Opacity'
    'Highlight Auto Text Color'
    'Highlight Text Color'
    'Highlight Auto Greentext Color'
    'Highlight Greentext Color'
    'Highlight Auto Title Color'
    'Highlight Title Color'
    'Highlight Auto Link Color'
    'Highlight Link Color'
  ]

  init: ->
    for key in @generatedKeys
      $.sync key, @syncGenerated
    @updateGeneratedStyles()

    return unless Conf['Custom CSS']
    return unless g.VIEW or Conf['Custom CSS on Homepage']
    @addStyle()

    # On boardless pages (homepage, etc.), Chrome sometimes ends up with
    # late page styles overriding or replacing our node on reload.
    return if g.VIEW
    refresh = =>
      @ensureStyle()
      $.queueTask @ensureStyle.bind(@)
    $.ready refresh
    $.on window, 'pageshow load', refresh
    @watchHomepageHead()

  syncGenerated: (value, key) ->
    Conf[key] = value
    CustomCSS.updateGeneratedStyles()

  addStyle: ->
    # On board pages append after 4chan-eX base CSS; on boardless pages inject as soon as <head> exists.
    anchor = if g.BOARD then '#fourchanx-css' else 'head'
    @style = $.addStyle CSS.sub(Conf['usercss']), 'custom-css', anchor

  ensureStyle: ->
    style = $.id 'custom-css'
    unless style
      @addStyle()
      return

    css = CSS.sub Conf['usercss']
    style.textContent = css if style.textContent isnt css
    style.disabled = false if style.disabled
    @style = style

    return unless d.head
    if style.parentNode isnt d.head or d.head.lastElementChild isnt style
      $.add d.head, style

  addGeneratedStyle: ->
    anchor = if g.BOARD then '#fourchanx-css' else 'head'
    @generatedStyle = $.addStyle CSS.sub(@generatedHighlightCSS()), 'custom-generated-highlights', anchor

  rmGeneratedStyle: ->
    if @generatedStyle
      $.rm @generatedStyle
      delete @generatedStyle

  updateGeneratedStyles: ->
    unless g.VIEW and Conf['Generated Highlight Styles']
      return @rmGeneratedStyle()
    css = CSS.sub @generatedHighlightCSS()
    unless @generatedStyle
      return @addGeneratedStyle()
    @generatedStyle.textContent = css if @generatedStyle.textContent isnt css
    @generatedStyle.disabled = false if @generatedStyle.disabled

  generatedHighlightSettings: ->
    watchedColor = @normalizeHexColor Conf['Highlight Watched Color'], '#00509b'
    yourPostColor = @normalizeHexColor Conf['Highlight Your Post Color'], '#059600'
    quotesYouColor = @normalizeHexColor Conf['Highlight Quotes You Color'], '#ad2c27'
    ghostPostColor = @normalizeHexColor Conf['Highlight Ghost Post Color'], '#666666'
    watchedOpacity = @normalizeNumber Conf['Highlight Watched Opacity'], 1, 0, 1
    yourPostOpacity = @normalizeNumber Conf['Highlight Your Post Opacity'], 0.7, 0, 1
    quotesYouOpacity = @normalizeNumber Conf['Highlight Quotes You Opacity'], 0.8, 0, 1
    ghostPostOpacity = @normalizeNumber Conf['Highlight Ghost Post Opacity'], 0.5, 0, 1
    autoTextColor = Conf['Highlight Auto Text Color'] isnt false
    manualTextColor = @normalizeHexColor Conf['Highlight Text Color'], '#f2f2f2'
    autoGreentextColor = Conf['Highlight Auto Greentext Color'] isnt false
    manualGreentextColor = @normalizeHexColor Conf['Highlight Greentext Color'], '#789922'
    autoTitleColor = Conf['Highlight Auto Title Color'] isnt false
    manualTitleColor = @normalizeHexColor Conf['Highlight Title Color'], '#0f0c5d'
    autoLinkColor = Conf['Highlight Auto Link Color'] isnt false
    manualLinkColor = @normalizeHexColor Conf['Highlight Link Color'], '#99c3ff'
    referenceBackgroundRGB = @generatedHighlightReferenceBackground()
    watchedFillRGB = @blendedFillRGB watchedColor, watchedOpacity, referenceBackgroundRGB
    yourPostFillRGB = @blendedFillRGB yourPostColor, yourPostOpacity, referenceBackgroundRGB
    yourPostBorderColor = @autoBorderColor yourPostColor, yourPostOpacity, referenceBackgroundRGB
    quotesYouBorderColor = @autoBorderColor quotesYouColor, quotesYouOpacity, referenceBackgroundRGB
    ghostPostBorderColor = @autoBorderColor ghostPostColor, ghostPostOpacity, referenceBackgroundRGB
    watchedQuoteColor = @autoQuoteColor watchedColor, watchedOpacity, referenceBackgroundRGB
    yourPostQuoteColor = @autoQuoteColor yourPostColor, yourPostOpacity, referenceBackgroundRGB
    quotesYouQuoteColor = @autoQuoteColor quotesYouColor, quotesYouOpacity, referenceBackgroundRGB
    watchedAutoLinkColor = @autoLinkColor watchedColor, watchedOpacity, referenceBackgroundRGB
    yourPostAutoLinkColor = @autoLinkColor yourPostColor, yourPostOpacity, referenceBackgroundRGB
    quotesYouAutoLinkColor = @autoLinkColor quotesYouColor, quotesYouOpacity, referenceBackgroundRGB
    watchedSubjectColor = @autoTitleColor watchedColor, watchedOpacity, referenceBackgroundRGB, 4.0
    yourPostSubjectColor = @autoTitleColor yourPostColor, yourPostOpacity, referenceBackgroundRGB, 4.0

    {
      watchedColor
      watchedOpacity
      yourPostColor
      yourPostOpacity
      quotesYouColor
      quotesYouOpacity
      ghostPostColor
      ghostPostOpacity
      referenceBackgroundRGB
      referenceBackgroundCSS: @rgbCSS referenceBackgroundRGB
      referenceTextColor: @autoBaseTextColor referenceBackgroundRGB
      yourPostBorderColor
      quotesYouBorderColor
      ghostPostBorderColor
      watchedRGBA: @toRGBA watchedColor, watchedOpacity
      yourPostRGBA: @toRGBA yourPostColor, yourPostOpacity
      quotesYouRGBA: @toRGBA quotesYouColor, quotesYouOpacity
      ghostPostRGBA: @toRGBA ghostPostColor, ghostPostOpacity
      yourPostBorderRGBA: @toRGBA yourPostBorderColor, 1
      quotesYouBorderRGBA: @toRGBA quotesYouBorderColor, 1
      ghostPostBorderRGBA: @toRGBA ghostPostBorderColor, 1
      watchedTextColor: if autoTextColor then @autoTextColor watchedColor, watchedOpacity, referenceBackgroundRGB else manualTextColor
      yourPostTextColor: if autoTextColor then @autoTextColor yourPostColor, yourPostOpacity, referenceBackgroundRGB else manualTextColor
      quotesYouTextColor: if autoTextColor then @autoTextColor quotesYouColor, quotesYouOpacity, referenceBackgroundRGB else manualTextColor
      watchedQuoteColor: if autoGreentextColor then watchedQuoteColor else manualGreentextColor
      yourPostQuoteColor: if autoGreentextColor then yourPostQuoteColor else manualGreentextColor
      quotesYouQuoteColor: if autoGreentextColor then quotesYouQuoteColor else manualGreentextColor
      watchedSubjectColor: if autoTitleColor then watchedSubjectColor else manualTitleColor
      yourPostSubjectColor: if autoTitleColor then yourPostSubjectColor else manualTitleColor
      watchedLinkColor: if autoLinkColor then watchedAutoLinkColor else manualLinkColor
      yourPostLinkColor: if autoLinkColor then yourPostAutoLinkColor else manualLinkColor
      quotesYouLinkColor: if autoLinkColor then quotesYouAutoLinkColor else manualLinkColor
    }

  generatedHighlightCSS: ->
    styles = @generatedHighlightSettings()
    """
      /* Auto-generated Highlight Styles (4chan-eX) */
      :root {
        --eX-your-post-color: #{styles.yourPostColor};
        --eX-quotes-you-color: #{styles.quotesYouColor};
        --eX-ghost-post-color: #{styles.ghostPostColor};
        --eX-watched-color: #{styles.watchedColor};
        --eX-your-post-border: #{styles.yourPostBorderRGBA};
        --eX-quotes-you-border: #{styles.quotesYouBorderRGBA};
        --eX-ghost-post-border: #{styles.ghostPostBorderRGBA};
      }
      :root .watched {
        background: #{styles.watchedRGBA} !important;
        color: #{styles.watchedTextColor} !important;
      }
      :root .watched a,
      :root .watched .quotelink,
      :root .watched .deadlink {
        color: #{styles.watchedLinkColor} !important;
      }
      :root .watched .postNum > a,
      :root .watched .name,
      :root .watched .dateTime,
      :root .watched .postNum {
        color: inherit !important;
      }
      :root .watched .quote {
        color: #{styles.watchedQuoteColor} !important;
      }
      :root .watched .subject {
        color: #{styles.watchedSubjectColor} !important;
      }

      :root.highlight-own .watched:has(> .yourPost) {
        background: #{styles.yourPostRGBA} !important;
      }

      :root.highlight-own .watched > .yourPost {
        background: #{styles.yourPostRGBA} !important;
      }

      :root.highlight-own .watched:has(> .yourPost) > .yourPost {
        background: transparent !important;
      }
      :root.highlight-own .watched:has(> .yourPost) .subject,
      :root.highlight-own .watched > .yourPost .subject {
        color: #{styles.yourPostSubjectColor} !important;
      }

      :root.highlight-own :not(.watched) > .yourPost:not(.opContainer) div.post {
        background: #{styles.yourPostRGBA} !important;
        color: #{styles.yourPostTextColor} !important;
      }
      :root.highlight-own :not(.watched) > .yourPost:not(.opContainer) div.post a,
      :root.highlight-own :not(.watched) > .yourPost:not(.opContainer) div.post .quotelink,
      :root.highlight-own :not(.watched) > .yourPost:not(.opContainer) div.post .deadlink {
        color: #{styles.yourPostLinkColor} !important;
      }
      :root.highlight-own :not(.watched) > .yourPost:not(.opContainer) div.post .postNum > a,
      :root.highlight-own :not(.watched) > .yourPost:not(.opContainer) div.post .name,
      :root.highlight-own :not(.watched) > .yourPost:not(.opContainer) div.post .dateTime,
      :root.highlight-own :not(.watched) > .yourPost:not(.opContainer) div.post .postNum {
        color: inherit !important;
      }
      :root.highlight-own :not(.watched) > .yourPost:not(.opContainer) div.post .quote {
        color: #{styles.yourPostQuoteColor} !important;
      }

      :root.highlight-own.highlight-own.highlight-own .yourPost > .op,
      :root.highlight-own.highlight-own.highlight-own .yourPost > .reply {
        border-left: 3px dashed #{styles.yourPostBorderRGBA} !important;
      }

      :root.highlight-you .replyContainer.quotesYou > .reply,
      :root.highlight-you .postContainer.quotesYou > .reply,
      :root.highlight-you .opContainer.quotesYou > .op {
        background: #{styles.quotesYouRGBA} !important;
        color: #{styles.quotesYouTextColor} !important;
      }
      :root.highlight-you.highlight-you.highlight-you .quotesYou > .op,
      :root.highlight-you.highlight-you.highlight-you .quotesYou > .reply {
        border-left: 3px solid #{styles.quotesYouBorderRGBA} !important;
      }
      :root.highlight-you .replyContainer.quotesYou > .reply a,
      :root.highlight-you .postContainer.quotesYou > .reply a,
      :root.highlight-you .opContainer.quotesYou > .op a,
      :root.highlight-you .replyContainer.quotesYou > .reply .quotelink,
      :root.highlight-you .postContainer.quotesYou > .reply .quotelink,
      :root.highlight-you .opContainer.quotesYou > .op .quotelink,
      :root.highlight-you .replyContainer.quotesYou > .reply .deadlink,
      :root.highlight-you .postContainer.quotesYou > .reply .deadlink,
      :root.highlight-you .opContainer.quotesYou > .op .deadlink {
        color: #{styles.quotesYouLinkColor} !important;
      }
      :root.highlight-you .replyContainer.quotesYou > .reply .postNum > a,
      :root.highlight-you .postContainer.quotesYou > .reply .postNum > a,
      :root.highlight-you .opContainer.quotesYou > .op .postNum > a,
      :root.highlight-you .replyContainer.quotesYou > .reply .name,
      :root.highlight-you .postContainer.quotesYou > .reply .name,
      :root.highlight-you .opContainer.quotesYou > .op .name,
      :root.highlight-you .replyContainer.quotesYou > .reply .dateTime,
      :root.highlight-you .postContainer.quotesYou > .reply .dateTime,
      :root.highlight-you .opContainer.quotesYou > .op .dateTime,
      :root.highlight-you .replyContainer.quotesYou > .reply .postNum,
      :root.highlight-you .postContainer.quotesYou > .reply .postNum,
      :root.highlight-you .opContainer.quotesYou > .op .postNum {
        color: inherit !important;
      }
      :root.highlight-you .replyContainer.quotesYou > .reply .quote,
      :root.highlight-you .postContainer.quotesYou > .reply .quote,
      :root.highlight-you .opContainer.quotesYou > .op .quote {
        color: #{styles.quotesYouQuoteColor} !important;
      }

      :root.highlight-ghost .ghost-post > .post,
      :root.highlight-ghost .ghost-post.opContainer > .post.op {
        background: #{styles.ghostPostRGBA} !important;
        border-left: 3px dotted #{styles.ghostPostBorderRGBA} !important;
      }
    """

  generatedHighlightPreviewCSS: ->
    styles = @generatedHighlightSettings()
    """
      .section-styling .ghs-catalog-preview,
      .section-styling .ghs-thread-preview {
        background: transparent;
        color: #{styles.referenceTextColor};
      }
      .section-styling .ghs-thread-preview > div {
        background: transparent;
      }

      .section-styling .ghs-catalog-thread.watched {
        background: #{styles.watchedRGBA};
        color: #{styles.watchedTextColor};
      }
      .section-styling .ghs-catalog-thread.watched .ghs-catalog-stats,
      .section-styling .ghs-catalog-thread.watched .ghs-catalog-comment {
        color: inherit !important;
      }
      .section-styling .ghs-catalog-thread.watched .ghs-catalog-subject,
      .section-styling .ghs-catalog-thread.watched .subject {
        color: #{styles.watchedSubjectColor} !important;
      }

      .section-styling .ghs-catalog-thread.watched.ghs-watched-you {
        background: #{styles.yourPostRGBA};
        color: #{styles.yourPostTextColor} !important;
      }

      .section-styling .ghs-catalog-thread.watched.ghs-watched-you > .yourPost {
        background: transparent;
        color: #{styles.yourPostTextColor} !important;
      }
      .section-styling .ghs-catalog-thread.watched.ghs-watched-you .ghs-catalog-stats,
      .section-styling .ghs-catalog-thread.watched.ghs-watched-you .ghs-catalog-comment {
        color: #{styles.yourPostTextColor} !important;
      }
      .section-styling .ghs-catalog-thread.watched.ghs-watched-you .ghs-catalog-subject,
      .section-styling .ghs-catalog-thread.watched.ghs-watched-you .subject {
        color: #{styles.yourPostSubjectColor} !important;
      }

      .section-styling .ghs-thread-preview .postContainer.replyContainer.yourPost:not(.opContainer) .post.reply {
        background: #{styles.yourPostRGBA};
        color: #{styles.yourPostTextColor};
        border-left: 3px dashed #{styles.yourPostBorderRGBA} !important;
      }
      .section-styling .ghs-thread-preview .postContainer.replyContainer.yourPost:not(.opContainer) .post.reply .quote {
        color: #{styles.yourPostQuoteColor} !important;
      }

      .section-styling .ghs-thread-preview.highlight-you .replyContainer.quotesYou > .reply,
      .section-styling .ghs-thread-preview.highlight-you .postContainer.quotesYou > .reply,
      .section-styling .ghs-thread-preview.highlight-you .opContainer.quotesYou > .op {
        background: #{styles.quotesYouRGBA};
        color: #{styles.quotesYouTextColor};
        border-left: 3px solid #{styles.quotesYouBorderRGBA} !important;
      }
      .section-styling .ghs-thread-preview.highlight-you .replyContainer.quotesYou > .reply .quote,
      .section-styling .ghs-thread-preview.highlight-you .postContainer.quotesYou > .reply .quote,
      .section-styling .ghs-thread-preview.highlight-you .opContainer.quotesYou > .op .quote {
        color: #{styles.quotesYouQuoteColor} !important;
      }
      .section-styling .ghs-catalog-thread.watched a,
      .section-styling .ghs-catalog-thread.watched .quotelink,
      .section-styling .ghs-catalog-thread.watched .deadlink {
        color: #{styles.watchedLinkColor} !important;
      }
      .section-styling .ghs-catalog-thread.watched.ghs-watched-you a,
      .section-styling .ghs-catalog-thread.watched.ghs-watched-you .quotelink,
      .section-styling .ghs-catalog-thread.watched.ghs-watched-you .deadlink {
        color: #{styles.yourPostLinkColor} !important;
      }
      .section-styling .ghs-thread-preview .postContainer.replyContainer.yourPost:not(.opContainer) .post.reply a,
      .section-styling .ghs-thread-preview .postContainer.replyContainer.yourPost:not(.opContainer) .post.reply .quotelink,
      .section-styling .ghs-thread-preview .postContainer.replyContainer.yourPost:not(.opContainer) .post.reply .deadlink {
        color: #{styles.yourPostLinkColor} !important;
      }
      .section-styling .ghs-thread-preview.highlight-you .replyContainer.quotesYou > .reply a,
      .section-styling .ghs-thread-preview.highlight-you .postContainer.quotesYou > .reply a,
      .section-styling .ghs-thread-preview.highlight-you .opContainer.quotesYou > .op a,
      .section-styling .ghs-thread-preview.highlight-you .replyContainer.quotesYou > .reply .quotelink,
      .section-styling .ghs-thread-preview.highlight-you .postContainer.quotesYou > .reply .quotelink,
      .section-styling .ghs-thread-preview.highlight-you .opContainer.quotesYou > .op .quotelink,
      .section-styling .ghs-thread-preview.highlight-you .replyContainer.quotesYou > .reply .deadlink,
      .section-styling .ghs-thread-preview.highlight-you .postContainer.quotesYou > .reply .deadlink,
      .section-styling .ghs-thread-preview.highlight-you .opContainer.quotesYou > .op .deadlink {
        color: #{styles.quotesYouLinkColor} !important;
      }

      .section-styling .ghs-thread-preview.highlight-ghost .ghost-post > .post,
      .section-styling .ghs-thread-preview.highlight-ghost .ghost-post.opContainer > .post.op {
        background: #{styles.ghostPostRGBA} !important;
        border-left: 3px dotted #{styles.ghostPostBorderRGBA} !important;
      }
    """

  normalizeHexColor: (color, fallback) ->
    return fallback unless typeof color is 'string'
    color = color.trim().toLowerCase()
    if /^#[\da-f]{3}$/.test color
      return '#' + color[1..].split('').map((x) -> x + x).join('')
    return color if /^#[\da-f]{6}$/.test color
    fallback

  normalizeNumber: (value, fallback, min, max) ->
    n = parseFloat value
    n = fallback unless isFinite n
    n = Math.max min, Math.min(max, n)
    Math.round(n * 100) / 100

  toRGBA: (hex, opacity) ->
    r = parseInt hex[1..2], 16
    g = parseInt hex[3..4], 16
    b = parseInt hex[5..6], 16
    "rgba(#{r}, #{g}, #{b}, #{opacity})"

  autoTextColor: (hex, opacity, backgroundRGB=[0, 0, 0]) ->
    fill = @blendedFillRGB hex, opacity, backgroundRGB
    dark = {r: 17, g: 17, b: 17}
    light = {r: 242, g: 242, b: 242}
    darkContrast = @contrastRatio dark, fill
    lightContrast = @contrastRatio light, fill
    if darkContrast >= lightContrast then '#111' else '#f2f2f2'

  autoBorderColor: (hex, opacity, backgroundRGB=[0, 0, 0]) ->
    base = @blendedFillRGB hex, opacity, backgroundRGB
    fillLuma = @luma base.r, base.g, base.b
    target = if fillLuma >= 145 then {r: 0, g: 0, b: 0} else {r: 255, g: 255, b: 255}
    border = @mixRGB base, target, 0.68

    # Ensure strong contrast against the highlighted fill.
    minContrast = 2.0
    if @contrastRatio(border, base) < minContrast
      for amount in [0.78, 0.86, 0.94]
        border = @mixRGB base, target, amount
        break if @contrastRatio(border, base) >= minContrast

    @rgbToHex border.r, border.g, border.b

  autoQuoteColor: (hex, opacity, backgroundRGB=[0, 0, 0]) ->
    fill = @blendedFillRGB hex, opacity, backgroundRGB
    baseGreen = {r: 120, g: 153, b: 34} # #789922
    minContrast = 3.0

    # Keep quote color as close to classic greentext as possible.
    return @rgbToHex(baseGreen.r, baseGreen.g, baseGreen.b) if @contrastRatio(baseGreen, fill) >= minContrast

    fillLuma = @luma fill.r, fill.g, fill.b
    target = if fillLuma >= 145 then {r: 0, g: 0, b: 0} else {r: 255, g: 255, b: 255}

    # Nudge in small steps first; only push further if needed for readability.
    steps = [0.08, 0.16, 0.24, 0.32, 0.42, 0.54, 0.68]
    best = baseGreen
    bestContrast = @contrastRatio(baseGreen, fill)
    for amount in steps
      quote = @mixRGB baseGreen, target, amount
      contrast = @contrastRatio quote, fill
      if contrast > bestContrast
        best = quote
        bestContrast = contrast
      if contrast >= minContrast
        return @rgbToHex quote.r, quote.g, quote.b

    @rgbToHex best.r, best.g, best.b

  autoLinkColor: (hex, opacity, backgroundRGB=[0, 0, 0]) ->
    fill = @blendedFillRGB hex, opacity, backgroundRGB
    baseBlue = {r: 59, g: 112, b: 217} # #3b70d9
    minContrast = 3.0

    return @rgbToHex(baseBlue.r, baseBlue.g, baseBlue.b) if @contrastRatio(baseBlue, fill) >= minContrast

    fillLuma = @luma fill.r, fill.g, fill.b
    target = if fillLuma >= 145 then {r: 0, g: 0, b: 0} else {r: 255, g: 255, b: 255}
    steps = [0.08, 0.16, 0.24, 0.32, 0.42, 0.54, 0.68]
    best = baseBlue
    bestContrast = @contrastRatio(baseBlue, fill)
    for amount in steps
      link = @mixRGB baseBlue, target, amount
      contrast = @contrastRatio link, fill
      if contrast > bestContrast
        best = link
        bestContrast = contrast
      if contrast >= minContrast
        return @rgbToHex link.r, link.g, link.b

    @rgbToHex best.r, best.g, best.b

  autoTitleColor: (hex, opacity, backgroundRGB=[0, 0, 0], minContrast=5.5) ->
    fill = @blendedFillRGB hex, opacity, backgroundRGB
    fillLuma = @luma fill.r, fill.g, fill.b
    dark = {r: 0, g: 0, b: 0}
    light = {r: 255, g: 255, b: 255}
    # Prefer darker title shades unless the background is clearly dark.
    primaryTarget = if fillLuma > 110 then dark else light
    secondaryTarget = if primaryTarget is dark then light else dark

    # Keep title close to selected highlight color, then shift lighter/darker as needed.
    steps = [0.12, 0.2, 0.3, 0.42, 0.56, 0.7, 0.84, 0.92, 0.97]
    pickFor = (target) =>
      best = fill
      bestContrast = 1
      for amount in steps
        shade = @mixRGB fill, target, amount
        contrast = @contrastRatio shade, fill
        if contrast > bestContrast
          best = shade
          bestContrast = contrast
        if contrast >= minContrast
          return {done: true, color: shade, contrast}
      targetContrast = @contrastRatio target, fill
      if targetContrast > bestContrast
        best = target
        bestContrast = targetContrast
      {done: false, color: best, contrast: bestContrast}

    primary = pickFor primaryTarget
    return @rgbToHex(primary.color.r, primary.color.g, primary.color.b) if primary.done

    secondary = pickFor secondaryTarget
    winner = if secondary.contrast > primary.contrast then secondary else primary
    @rgbToHex winner.color.r, winner.color.g, winner.color.b

  randomGeneratedHighlightColors: ->
    [bgR, bgG, bgB] = @generatedHighlightReferenceBackground()
    bgRGB = {r: bgR, g: bgG, b: bgB}
    isDark = @luma(bgR, bgG, bgB) < 128

    baseHue = Math.random() * 360
    dir = if Math.random() < 0.5 then 1 else -1
    offset1 = dir * (90 + Math.random() * 50)
    offset2 = dir * (200 + Math.random() * 50)
    hues = (
      ((((baseHue + delta) % 360) + 360) % 360) for delta in [0, offset1, offset2]
    )

    roles = ['watched', 'yourPost', 'quotesYou']
    for i in [roles.length - 1..1] by -1
      j = Math.floor(Math.random() * (i + 1))
      [roles[i], roles[j]] = [roles[j], roles[i]]

    pickColor = (hue) =>
      sat = 0.6 + Math.random() * 0.28
      light = if isDark then 0.42 + Math.random() * 0.2 else 0.32 + Math.random() * 0.15
      color = @hslToRGB hue, sat, light
      attempts = 0
      while attempts < 8 and @contrastRatio(color, bgRGB) < 2.4
        light = if isDark then Math.min(0.74, light + 0.06) else Math.max(0.18, light - 0.06)
        color = @hslToRGB hue, sat, light
        attempts++
      @rgbToHex color.r, color.g, color.b

    result = $.dict()
    result[roles[i]] = pickColor(hues[i]) for i in [0...3]
    result

  hslToRGB: (h, s, l) ->
    h = ((h % 360) + 360) % 360
    s = Math.max 0, Math.min(1, s)
    l = Math.max 0, Math.min(1, l)
    c = (1 - Math.abs(2 * l - 1)) * s
    x = c * (1 - Math.abs(((h / 60) % 2) - 1))
    m = l - c / 2
    [r1, g1, b1] = switch
      when h <  60 then [c, x, 0]
      when h < 120 then [x, c, 0]
      when h < 180 then [0, c, x]
      when h < 240 then [0, x, c]
      when h < 300 then [x, 0, c]
      else              [c, 0, x]
    {
      r: Math.round((r1 + m) * 255)
      g: Math.round((g1 + m) * 255)
      b: Math.round((b1 + m) * 255)
    }

  generatedHighlightReferenceBackground: ->
    return [18, 18, 18] unless d?.body
    node = $('.post.reply, .post.op, .post') or d.body
    bg = {r: 0, g: 0, b: 0, a: 0}

    while node
      color = @parseCSSColor getComputedStyle(node).backgroundColor
      bg = @compositeRGBA color, bg if color
      return [Math.round(bg.r), Math.round(bg.g), Math.round(bg.b)] if bg.a >= 0.98
      node = node.parentElement

    [18, 18, 18]

  compositeRGBA: (fg, bg) ->
    alpha = fg.a + bg.a * (1 - fg.a)
    return {r: 0, g: 0, b: 0, a: 0} unless alpha

    {
      r: (fg.r * fg.a + bg.r * bg.a * (1 - fg.a)) / alpha
      g: (fg.g * fg.a + bg.g * bg.a * (1 - fg.a)) / alpha
      b: (fg.b * fg.a + bg.b * bg.a * (1 - fg.a)) / alpha
      a: alpha
    }

  parseCSSColor: (value) ->
    return null unless typeof value is 'string'
    match = value.match /^rgba?\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)(?:\s*[,/]\s*([\d.]+))?\s*\)$/i
    return null unless match
    r = Math.max 0, Math.min(255, parseFloat(match[1]) or 0)
    g = Math.max 0, Math.min(255, parseFloat(match[2]) or 0)
    b = Math.max 0, Math.min(255, parseFloat(match[3]) or 0)
    a = Math.max 0, Math.min(1, if match[4]? then parseFloat(match[4]) else 1)
    {r, g, b, a}

  hexToRGB: (hex) ->
    r = parseInt hex[1..2], 16
    g = parseInt hex[3..4], 16
    b = parseInt hex[5..6], 16
    {r, g, b}

  mixRGB: (base, target, amount) ->
    amount = Math.max 0, Math.min 1, amount
    inv = 1 - amount
    {
      r: Math.round base.r * inv + target.r * amount
      g: Math.round base.g * inv + target.g * amount
      b: Math.round base.b * inv + target.b * amount
    }

  blendedFillRGB: (hex, opacity, backgroundRGB=[0, 0, 0]) ->
    {r, g, b} = @hexToRGB hex
    [bgR, bgG, bgB] = backgroundRGB
    {
      r: Math.round r * opacity + bgR * (1 - opacity)
      g: Math.round g * opacity + bgG * (1 - opacity)
      b: Math.round b * opacity + bgB * (1 - opacity)
    }

  rgbToHex: (r, g, b) ->
    '#' + [r, g, b].map((n) ->
      hex = Math.max(0, Math.min(255, Math.round(n))).toString 16
      if hex.length is 1 then "0#{hex}" else hex
    ).join('')

  rgbCSS: ([r, g, b]) ->
    "rgb(#{Math.round(r)}, #{Math.round(g)}, #{Math.round(b)})"

  luma: (r, g, b) ->
    0.299 * r + 0.587 * g + 0.114 * b

  autoBaseTextColor: ([r, g, b]) ->
    if @luma(r, g, b) >= 145 then '#111' else '#f2f2f2'

  contrastRatio: (a, b) ->
    l1 = @relativeLuminance a.r, a.g, a.b
    l2 = @relativeLuminance b.r, b.g, b.b
    hi = Math.max l1, l2
    lo = Math.min l1, l2
    (hi + 0.05) / (lo + 0.05)

  relativeLuminance: (r, g, b) ->
    [r, g, b] = [r, g, b].map (n) ->
      c = (Math.max(0, Math.min(255, n)) / 255)
      if c <= 0.04045 then c / 12.92 else Math.pow((c + 0.055) / 1.055, 2.4)
    0.2126 * r + 0.7152 * g + 0.0722 * b

  watchHomepageHead: ->
    return if @headObserver
    $.onExists doc, 'head', =>
      @ensureStyle()
      @headObserver = new MutationObserver =>
        @ensureStyle()
      @headObserver.observe d.head, {childList: true}

  rmStyle: ->
    if @style
      $.rm @style
      delete @style

  update: ->
    @updateGeneratedStyles()
    return unless Conf['Custom CSS']
    unless @style
      return @addStyle()
    @style.textContent = CSS.sub Conf['usercss']
    @ensureStyle() unless g.VIEW
