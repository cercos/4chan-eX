QRMetadataPatch =
  updateNotice: (post, message, type) ->
    notice = post._metadataNotice
    if !notice
      post._metadataNotice = notice = new Notice(type or 'info', message)
      return notice
    notice.setType(type) if type
    if notice.el?.lastElementChild
      notice.el.lastElementChild.textContent = ''
      $.add notice.el.lastElementChild, $.tn(message)
    notice

  closeNotice: (post) ->
    if post._metadataNotice
      post._metadataNotice.close()
      delete post._metadataNotice

  replaceExtension: (name, ext) ->
    base = (name or 'file').replace(/\.[^.\/\\]+$/, '')
    "#{base}.#{ext}"

  fileGroup: (file) ->
    type = (file?.type or '').toLowerCase()
    name = (file?.name or '').toLowerCase()
    return 'image' if /^image\//.test(type) or /\.(jpe?g|png|gif|webp|bmp|avif|heic|heif)$/.test(name)
    return 'video' if /^video\//.test(type) or /\.(webm|mp4|m4v|mov|3gp|3g2|mkv)$/.test(name)
    return 'audio' if /^audio\//.test(type) or /\.(mp3|m4a|aac|ogg|opus|wav|flac|weba)$/.test(name)
    'other'

  settingEnabled: (name, legacyName) ->
    val = Conf[name]
    return val if typeof val is 'boolean'
    if legacyName?
      legacy = Conf[legacyName]
      return legacy if typeof legacy is 'boolean'
    false

  shouldStrip: (file) ->
    return false unless file
    return true if Conf['Strip All Media Metadata']
    switch QRMetadataPatch.fileGroup(file)
      when 'image' then QRMetadataPatch.settingEnabled('Image Metadata', 'Strip Image Metadata')
      when 'video' then QRMetadataPatch.settingEnabled('Video Metadata', 'Strip Video Metadata')
      when 'audio' then QRMetadataPatch.settingEnabled('Audio Metadata', 'Strip Audio Metadata')
      else QRMetadataPatch.settingEnabled('Other Metadata', 'Strip Other Media Metadata')

  setMp4BoxType: (bytes, start, type) ->
    return unless start + 8 <= bytes.length and type?.length is 4
    bytes[start + 4] = type.charCodeAt(0)
    bytes[start + 5] = type.charCodeAt(1)
    bytes[start + 6] = type.charCodeAt(2)
    bytes[start + 7] = type.charCodeAt(3)

  zeroBytes: (bytes, start, finish) ->
    return unless start < finish
    start = Math.max(0, start)
    finish = Math.min(bytes.length, finish)
    for i in [start...finish]
      bytes[i] = 0

  zeroMp4Times: (bytes, box) ->
    start = box.dataStart
    return false unless start + 12 <= box.end
    version = bytes[start]
    if version is 1
      return false unless start + 20 <= box.end
      QRMetadataPatch.zeroBytes bytes, start + 4, start + 20
    else
      QRMetadataPatch.zeroBytes bytes, start + 4, start + 12
    true

  stripImage: (file, done) ->
    type = (file.type or '').toLowerCase()
    if type is 'image/gif'
      done null, null, 'unsupported'
      return

    url = URL.createObjectURL(file)
    img = $.el 'img'

    cleanup = ->
      URL.revokeObjectURL(url)
      img.onload = null
      img.onerror = null

    img.onerror = ->
      cleanup()
      done(new Error('Could not read image for metadata stripping.'))

    img.onload = ->
      try
        width = img.naturalWidth or img.width
        height = img.naturalHeight or img.height
        unless width and height
          cleanup()
          done(new Error('Image dimensions unavailable.'))
          return

        canvas = $.el 'canvas'
        canvas.width = width
        canvas.height = height
        canvas.getContext('2d').drawImage img, 0, 0, width, height

        targetType = switch
          when /^image\/jpeg$/i.test(type) then 'image/jpeg'
          when /^image\/png$/i.test(type)  then 'image/png'
          when /^image\/webp$/i.test(type) then 'image/webp'
          else 'image/png'
        quality = if targetType in ['image/jpeg', 'image/webp'] then 0.92 else null

        canvas.toBlob ((blob) ->
          cleanup()
          unless blob
            done(new Error('Could not encode stripped image.'))
            return
          ext = $.getOwn(QR.extensionFromType, targetType) or 'png'
          outFile = new File([blob], QRMetadataPatch.replaceExtension(file.name, ext), {type: targetType})
          done(null, outFile, 'stripped')
        ), targetType, quality
      catch err
        cleanup()
        done(err)

    img.src = url

  stripID3: (file, done) ->
    reader = new FileReader()
    reader.onerror = ->
      done(reader.error or new Error('Failed to read audio for metadata stripping.'))
    reader.onload = ->
      try
        bytes = new Uint8Array(reader.result)
        start = 0
        finish = bytes.length
        patched = false

        if bytes.length >= 10 and bytes[0] is 0x49 and bytes[1] is 0x44 and bytes[2] is 0x33
          tagSize =
            ((bytes[6] & 0x7F) << 21) |
            ((bytes[7] & 0x7F) << 14) |
            ((bytes[8] & 0x7F) << 7)  |
            (bytes[9] & 0x7F)
          flags = bytes[5] or 0
          hasFooter = !!(flags & 0x10)
          start = 10 + tagSize + (if hasFooter then 10 else 0)
          start = Math.min(start, finish)
          patched = true if start > 0

        if finish >= start + 128 and bytes[finish - 128] is 0x54 and bytes[finish - 127] is 0x41 and bytes[finish - 126] is 0x47
          finish -= 128
          patched = true

        unless patched
          done(null, null, 'unsupported')
          return

        outBytes = bytes.subarray(start, finish)
        outType = file.type or 'audio/mpeg'
        done(null, new File([outBytes], file.name, {type: outType}), 'stripped')
      catch err
        done(err)
    reader.readAsArrayBuffer(file)

  stripMp4Metadata: (file, done) ->
    videoPatch = window.QRVideoPatch
    unless videoPatch?.readMp4Box
      done(null, null, 'unsupported')
      return
    reader = new FileReader()
    reader.onerror = ->
      done(reader.error or new Error('Failed to read MP4 for metadata stripping.'))
    reader.onload = ->
      try
        buffer = reader.result
        bytes = new Uint8Array(buffer)
        view = new DataView(buffer)
        patched = false

        metadataBoxes =
          udta: true
          meta: true
          ilst: true
          keys: true
          cprt: true
          loci: true
          Xtra: true
          '----': true

        containerBoxes =
          moov: true
          trak: true
          mdia: true
          minf: true
          stbl: true
          edts: true
          dinf: true
          udta: true
          meta: true
          ilst: true
          moof: true
          traf: true
          mfra: true
          mvex: true

        timeBoxes =
          mvhd: true
          tkhd: true
          mdhd: true

        scanBoxes = (start, end) ->
          localPatch = false
          pos = start
          while pos < end
            box = videoPatch.readMp4Box(bytes, view, pos, end)
            break unless box and box.end > pos

            if box.type of metadataBoxes
              QRMetadataPatch.setMp4BoxType(bytes, box.start, 'free')
              localPatch = true
              pos = box.end
              continue

            if box.type of timeBoxes
              localPatch = QRMetadataPatch.zeroMp4Times(bytes, box) or localPatch

            if box.type of containerBoxes
              childStart = box.dataStart + (if box.type is 'meta' then 4 else 0)
              childStart = box.end if childStart > box.end
              localPatch = scanBoxes(childStart, box.end) or localPatch

            pos = box.end
          localPatch

        patched = scanBoxes(0, bytes.length)
        unless patched
          done(null, null, 'unsupported')
          return
        done(null, new File([bytes], file.name, {type: file.type or 'video/mp4'}), 'stripped')
      catch err
        done(err)
    reader.readAsArrayBuffer(file)

  stripWebMMetadata: (file, done) ->
    videoPatch = window.QRVideoPatch
    unless videoPatch?.readElement and videoPatch?.voidElement
      done(null, null, 'unsupported')
      return
    reader = new FileReader()
    reader.onerror = ->
      done(reader.error or new Error('Failed to read WebM for metadata stripping.'))
    reader.onload = ->
      try
        bytes = new Uint8Array(reader.result)
        patched = false
        pos = 0
        while pos < bytes.length
          top = videoPatch.readElement(bytes, pos, bytes.length)
          break unless top and top.end > pos
          if top.id is 0x18538067 # Segment
            segmentEnd = if top.sizeUnknown then bytes.length else top.dataEnd
            segPos = top.dataStart
            while segPos < segmentEnd
              child = videoPatch.readElement(bytes, segPos, segmentEnd)
              break unless child and child.end > segPos

              if child.id is 0x1254C367 # Tags
                if videoPatch.voidElement(bytes, child)
                  patched = true
              else if child.id is 0x1549A966 # Info
                infoPos = child.dataStart
                while infoPos < child.dataEnd
                  info = videoPatch.readElement(bytes, infoPos, child.dataEnd)
                  break unless info and info.end > infoPos
                  if info.id in [0x4461, 0x7BA9, 0x4D80, 0x5741, 0x73A4]
                    if videoPatch.voidElement(bytes, info)
                      patched = true
                  infoPos = info.end

              segPos = child.end
            break
          pos = top.end

        unless patched
          done(null, null, 'unsupported')
          return
        done(null, new File([bytes], file.name, {type: file.type or 'video/webm'}), 'stripped')
      catch err
        done(err)
    reader.readAsArrayBuffer(file)

  isLikelyMp4: (file) ->
    type = (file?.type or '').toLowerCase()
    name = (file?.name or '').toLowerCase()
    /^(video|audio)\/(mp4|quicktime|x-m4a)$/.test(type) or /\.(mp4|m4a|m4v|mov|3gp|3g2)$/.test(name)

  isLikelyWebM: (file) ->
    type = (file?.type or '').toLowerCase()
    name = (file?.name or '').toLowerCase()
    /(video|audio)\/webm/.test(type) or /\.(webm|mkv)$/.test(name)

  stripFile: (file, done) ->
    return done(null, null, 'unsupported') unless file
    group = QRMetadataPatch.fileGroup(file)

    if group is 'image'
      QRMetadataPatch.stripImage(file, done)
      return

    if QRMetadataPatch.isLikelyMp4(file)
      QRMetadataPatch.stripMp4Metadata(file, done)
      return

    if QRMetadataPatch.isLikelyWebM(file)
      QRMetadataPatch.stripWebMMetadata(file, done)
      return

    if group is 'audio'
      QRMetadataPatch.stripID3(file, done)
      return

    done(null, null, 'unsupported')

do ->
  proto = QR.post and QR.post.prototype
  return unless proto

  origSetFile = proto.setFile
  origRm = proto.rm
  origDelete = proto.delete
  origRmFile = proto.rmFile
  origSubmit = QR.submit

  proto.cancelMetadataProcessing = (message, silent) ->
    if @_metadataProcessing and @_metadataProcessing.stop
      @_metadataProcessing.cancelled = true
      @_metadataProcessing.stop()
      delete @_metadataProcessing
    if !@_imageProcessing and !@_videoProcessing
      delete @_pendingFile
    unless @file or @_imageProcessing or @_videoProcessing
      $.rmClass @nodes.el, 'has-file'
      @nodes.el.removeAttribute 'title'
      @nodes.span.textContent = @com or ''
    QRMetadataPatch.closeNotice(@)
    if !silent and message
      QR.notifications.push(new Notice('info', message, 4))

  proto.setFile = (file) ->
    post = @
    post._metadataTaskID = (post._metadataTaskID or 0) + 1
    taskID = post._metadataTaskID
    post.cancelMetadataProcessing(null, true)

    unless QRMetadataPatch.shouldStrip(file)
      return origSetFile.call(post, file)

    post.filename = file.name
    post._pendingFile = true
    $.addClass post.nodes.el, 'has-file'
    post.nodes.el.title = file.name
    post.nodes.span.textContent = file.name
    QR.updatePreviewStrip?()
    QRMetadataPatch.updateNotice(post, 'Stripping metadata...', 'info')
    post._metadataProcessing =
      stop: ->
        QRMetadataPatch.closeNotice(post)
      cancelled: false

    QRMetadataPatch.stripFile file, (err, outFile) ->
      return unless post._metadataTaskID is taskID
      delete post._metadataProcessing
      if !post._imageProcessing and !post._videoProcessing
        delete post._pendingFile
      if err
        QRMetadataPatch.closeNotice(post)
        unless post.file
          $.rmClass post.nodes.el, 'has-file'
        post.fileError(err.message or String(err))
        return
      if outFile
        setTimeout((-> QRMetadataPatch.closeNotice(post)), 1000)
        origSetFile.call(post, outFile)
      else
        QRMetadataPatch.closeNotice(post)
        origSetFile.call(post, file)

  proto.rm = ->
    @cancelMetadataProcessing(null, true)
    origRm.apply(@, arguments)

  proto.delete = ->
    @cancelMetadataProcessing(null, true)
    origDelete.apply(@, arguments)

  proto.rmFile = ->
    @cancelMetadataProcessing(null, true)
    origRmFile.apply(@, arguments)

  QR.submit = (e) ->
    if QR.selected and QR.selected._metadataProcessing
      e?.preventDefault?()
      QR.selected.cancelMetadataProcessing('Metadata processing canceled.')
      return
    origSubmit.apply(@, arguments)
