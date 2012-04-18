## Extension to Raphael to support adding & removign classes
Raphael.el.hasClass = (cls) ->
  (this.node.getAttribute('class') ? "").split(' ').indexOf(cls) != -1
  
Raphael.el.addClass = (cls) ->
  currentClass = (this.node.getAttribute('class') ? "").split(' ')
  return if currentClass.indexOf(cls) != -1
  
  currentClass.push(cls)
  this.node.setAttribute('class', currentClass.join(' '))
  return this

Raphael.el.removeClass = (cls) ->
  currentClass = (this.node.getAttribute('class') ? "").split(' ')
  position = currentClass.indexOf(cls)
  return if position == -1
  
  currentClass.splice(position, 1)
  this.node.setAttribute('class', currentClass.join(' '))
  return this

Raphael.el.toggleClass = (cls, bool) ->
  currentClass = (this.node.getAttribute('class') ? "").split(' ')
  currentClass.indexOf(cls)
  if bool?
    if bool then @addClass(cls) else @removeClass(cls)
  else
    if @hasClass(cls) then @removeClass(cls) else @addClass(cls)
  return this

## Custom arrow path
arrowPath = (x, y, width, height, tip, dir) ->
  """
    M
      #{x}
      #{y + height/2}
    L
      #{x+width}
      #{y + height/2}
    L
      #{x+width}
      #{y + height/2 + dir*(height - tip)}
    L
      #{x+width/2}
      #{y + height/2 + dir*height}
    L
      #{x}
      #{y + height/2 + dir*(height - tip)}
    Z
  """
  
## Mixin
Object.defineProperty Object.prototype, 'mixin', 
  value: (Mixin) ->
    this[key]   = value for key, value of Mixin
    this::[key] = value for key, value of Mixin.prototype
    return this
  enumerable: false

## Delayed function queue
Queue = []
Queue.run = ->
  return setTimeout Queue.run, 50 unless (fn = Queue.shift())?
  fn (next) ->
    Queue.push next if next?
    setTimeout Queue.run, 50
Queue.run()

## Naive set implementation
class Set
  @nextUid = 0
  
  add: (item) ->
    item.setId = Set.nextUid++ unless item.setId?
    this[item.setId] = item
  
  remove : (item) -> delete this[item.setId]
  has    : (item )-> item.setId? and this[item.setId]?

## Sync Mixin
# @property "propname", fnToCallOnPropChange
class Sync
  property: (names..., fn) ->
    for name in names then do (name) =>
      @properties ?= {}
      Object.defineProperty this, name, 
        set: (value) ->
          return if @properties[name] is value
          @properties[name] = value
          fn.call(this, value)
        get: -> 
          @properties[name]

## Wrapper around Array which maintains
#    - parent element
#    - next and previous siblings
#    - updates item on add
class Container extends Array
  push : (item) ->
    item.container = this
    item.index     = this.length
    item.dirty     = true
    item.root      = this.root
    super(item)
    Object.defineProperty item, "previous", get: -> @container[@index - 1]
    Object.defineProperty item, "next"    , get: -> @container[@index + 1]
    item.update()
    return item
  
  pair : ->
    n1 = Math.floor(Math.random()*@length)
    n2 = n1
    n2 = Math.floor(Math.random()*@length) while n1 == n2
    return [this[n1], this[n2]]
  
  swap : (item1, item2) ->
    @dirty = true
    item1.dirty = true
    item2.dirty = true
    
    index1 = item1.index
    index2 = item2.index
    
    this[item1.index = index2] = item1
    this[item2.index = index1] = item2
  
  move: (item, position) ->
    @dirty = true
    delta  = if position > item.index then 1 else - 1
    while item.index isnt position
      other = this[item.index + delta]
      @swap(item, other)

class Solver
  @diverge = 8
  
  constructor: (@crossings, @dir) ->
    @active  = false
    @subject = @crossings.container
  
  toggle: -> if @active then @stop() else @start()
  stop  : -> 
    @active        = false
    @subject.update()
    @subject.draw()
  
  start : ->
    @active = true
    @subject.update()
    @subject.draw()
    
    Queue.push step = (next) =>
      pairs = []
      costs = []
      
      startCost = minCost = @crossings[@dir]
      if cost is 0
        @stop()
        return next()
      
      @subject.root.updateCrossings = false
      
      for i in [0..Solver.diverge]
        pairs.push([el1, el2] = @subject.pair())
        @subject.swap(el1, el2)
        @subject.update()
        costs.push(cost = @crossings[@dir])
        minCost = Math.min(cost, minCost)
      
      for i in [Solver.diverge..0]
        break if (costs[i] == minCost and minCost isnt startCost)
        
        [el1, el2] = pairs[i]
        @subject.swap(el1, el2)
        @subject.update()
      
      if minCost is 0
        @stop()
        return next()
      
      @subject.root.updateCrossings = true
      @subject.root.draw()
      
      next(step if @active)

class Crossings
  @mixin Sync
  
  constructor: (@container, change) ->
    @property("up"  , (value) -> change("up"  , value))
    @property("down", (value) -> change("down", value))
    @properties.up   = 0
    @properties.down = 0
    
    @solver = 
      up   : new Solver this, "up"
      down : new Solver this, "down"

cross = (f1, t1, f2, t2) -> ((f1 < f2) and (t1 > t2)) or ((f1 > f2) and (t1 < t2))

class Edge
  @mixin Sync
  
  constructor: (@from, @to) ->
    @crossings = new Set
    @property "dirty", (dirty) ->
      if dirty
        @from.dirty = true
        @to.dirty = true
        @from.container.dirty = true
        @to.container.container.dirty = true
        @from.container.container.dirty = true
    
    @update()
  
  update: ->
    @dirty = true
    
    thisFromGroup   = this.from.container
    thisToGroup     = this.to.container
    thisFromSession = thisFromGroup.container
    thisToSession   = thisToGroup.container
    
    @from.root.updateCrossings = false
    
    for group in thisFromSession
      for mark in group
        for edge in mark when edge isnt this
          edgeFromGroup = edge.from.container
          edgeToGroup   = edge.to.container
          
          continue unless edgeFromGroup.container is thisFromSession
          
          delta = 0
          if cross(this.from.x, this.to.x, edge.from.x, edge.to.x)
            if not @crossings.has edge
              this.crossings.add edge
              edge.crossings.add this
              delta = 1
          else
            if @crossings.has edge
              this.crossings.remove edge
              edge.crossings.remove this
              delta = -1
          
          unless delta is 0
            thisFromGroup.crossings.global.down   += delta
            thisToGroup.crossings.global.up       += delta
            
            if thisFromGroup is edgeFromGroup
              thisFromGroup.crossings.local.down  += delta
            else
              edgeFromGroup.crossings.global.down += delta
            
            if thisToGroup   is edgeToGroup
              thisToGroup.crossings.local.up      += delta
            else
              edgeToGroup.crossings.global.up     += delta
            
            thisFromSession.crossings.down        += delta
            thisToSession.crossings.up            += delta
            
    @from.root.updateCrossings = false
  
  path: -> 
    @dirty = false
    """
      M
        #{@from.x+Mark.width/2} 
        #{@from.y+Mark.height}
      C
        #{@from.x+Mark.width/2} 
        #{(@from.y+Mark.height+@to.y)/2} 
        
        #{@to.x+Mark.width/2}
        #{(@from.y+Mark.height+@to.y)/2} 
        
        #{@to.x+Mark.width/2}
        #{@to.y}
    """

class Draggable
  dragStart : ->
    @startX = @x
  
  dragMove  : (dx, dy) ->
    @hasDragged = true
    @x = @startX + dx
    @update(@x)
    @draw()
    
    @root.updateCrossings = false
    while (other = @previous)?
      if @x + @width/2 < other.x + other.width/2
        @container.swap(this, other)
        other.update()
      else break
    
    while (other = @next)?
      if @x + @width/2 > other.x + other.width/2
        @container.swap(this, other)
        other.update()
      else break
    @root.updateCrossings = true
    @root.draw()
    
  dragEnd   : ->
    delete @startX
    @root.updateCrossings = true
    @update()
    @draw()
    @root.draw()
  

class Mark extends Array
  @mixin Sync
  @mixin Draggable
  
  @width  : 5
  @height : 30
  
  constructor: (@person) ->
    @property "dirty", (dirty) -> @person.dirty = true if dirty
    @property "x", "index", "active", -> @dirty = true
    
    @width  = Mark.width
    @height = Mark.height
    
    @shape  = paper.rect(0, 0, Mark.width, Mark.height/2, Mark.width/2)
                     .addClass('button mark')
                     .hide()
                     .drag(@dragMove.bind(this), @dragStart.bind(this), @dragEnd.bind(this))
    
  update: (x) ->
    @dirty = true
    @y = @container.y + Group.padding
    @x = x ? @container.x + Group.padding + @index * Mark.width
    edge.update() for edge in this
  
  path: ->
    """
    M
      #{@x+Mark.width/2} 
      #{@y}
    L
      #{@x+Mark.width/2} 
      #{@y+Mark.height}
    """ + (edge.path() for edge in this when edge.from is this).join()
  
  draw: ->
    return unless @dirty
    @person.draw()
    @shape.attr({x:@x, y:@y+Mark.height/4})
    
    if @active
      @shape.toFront().show()
    else
      @shape.hide()
    
    @dirty = false

class Group extends Container
  @mixin Sync
  @mixin Draggable
  
  @padding : 10
  @margin  : 20
  @height  : Group.padding + Mark.height + Group.padding
  @active  : null
  
  @select : (group) ->
    Group.select(null) if Group.selected? and group? and Group.selected isnt group
    
    if group?
      Group.selected   = group
      Session.selected = group.container
      
      group.selected  = true
      group.root.updateCrossings = true
      Group.selected.draw()
      $('#monitor').show()
    else
      if Group.selected
        Group.selected.selected = false
        Group.selected.draw()
      Group.selected = null
      $('#monitor').hide()
  
  constructor: ->
    @property "x", "index", -> 
      @dirty = true
    
    @property "dirty", (dirty) -> 
      mark.dirty = true for mark in this if dirty
    
    @property "selected", (selected) ->
      @dirty = true
      mark.person.highlighted = selected for mark in this
    
    @crossings = 
      local  : new Crossings(this, ((dir, crossings) => @renderCrossings "local" , dir))
      global : new Crossings(this, ((dir, crossings) => @renderCrossings "global", dir))
    
    @selected = false
    
    @height = Group.height
    @width  = 2 * Group.padding
    
    @hasDragged = false
    
    @shape = paper.rect(0, 0, 0, Group.height, 4, 4)
                    .addClass('button group')
                    .click(@click)
                    .drag(@dragMove.bind(this), @dragStart.bind(this), @dragEnd.bind(this))
  
  click     : =>
    Group.select(this unless Group.selected is this) unless @hasDragged
    @hasDragged = false
  
  push: (mark) ->
    @width += Mark.width
    super(mark)
  
  pair : ->
    for i in [1..@length]
      [m1, m2] = super()
      for e1 in m1
        for e2 in m2 when e1.crossings.has(e2)
          return [m1, m2]
    super()
  
  update: (x) ->
    @dirty = true
    @y = @container.y + Group.margin
    @x = x ? @container.filter((g) => g.index < @index).reduce(((x,g) -> x+g.width+Group.margin), @container.x )
    mark.update() for mark in this
  
  renderCrossings: (type, dir) ->
    return unless this is Group.selected and @root.updateCrossings
    $("##{type}-#{dir}").text(@crossings[type][dir])
  
  displayCrossings: ->
    @renderCrossings("local", "up")
    @renderCrossings("local", "down")
    @renderCrossings("global", "up")
    @renderCrossings("global", "down")
  
  computing: ->
    @crossings.local.solver.up.active   or
    @crossings.local.solver.down.active or
    @crossings.global.solver.up.active  or
    @crossings.global.solver.down.active
  
  draw: ->
    return unless @dirty
    @shape.attr({@x, @y, @width})
          .toggleClass('selected' , @selected)
          .toggleClass('computing', @computing())
    
    if @selected
      for type in ['local', 'global']
        for dir in ['up', 'down']
          $("##{type}-#{dir}-toggle").toggleClass('computing', @crossings[type].solver[dir].active)
    
    @displayCrossings() if @selected
    
    mark.draw() for mark in this
    @dirty = false

class Session extends Container
  @mixin Sync
  
  @buttonWidth  : 30
  @buttonHeight : 25
  @buttonTip    : 10
  @margin       : 140
  @separator    : 50
  @height       : Group.height + Session.separator
  
  constructor: ->
    @crossings = new Crossings(this, (dir, crossings) => @renderCrossings dir)
    
    @height = Session.height
    @x      = Session.margin
    
    @labels = 
      up   : paper.text(1.5 * Group.margin + Session.buttonWidth, 0, "").hide().addClass('session-label')
      down : paper.text(1.5 * Group.margin + Session.buttonWidth, 0, "").hide().addClass('session-label')
    
    @arrows = 
      up   : paper.path("M0 0").addClass('button session turn').hide().click(=> @click 'up')
      down : paper.path("M0 0").addClass('button session').hide().click(=> @click 'down')
    
  click: (dir) ->
    if (@previous? and dir is 'up') or (@next? and dir is 'down')
      @crossings.solver[dir].toggle()
  
  update: ->
    @dirty = true
    @y = if @previous? then @previous.y + Session.height else 0
    group.update() for group in this
    
  computing: ->
    @crossings.solver.up.active   or
    @crossings.solver.down.active
  
  renderCrossings: (dir) ->
    return unless @root.updateCrossings
    @labels[dir].attr "text", @crossings[dir]
    
  draw: (bubble) ->
    return unless @dirty
    if @previous?
      @labels.up.show().attr   'y', @y + Group.margin + Group.height/2 - 16
      @renderCrossings "up"
      @arrows.up.show().node.setAttribute   "d", arrowPath(Group.margin, @y + Group.margin + Group.height/2 - 5 - Session.buttonHeight/2, Session.buttonWidth, Session.buttonHeight, Session.buttonTip, -1)
      @arrows.up.toggleClass('computing', @crossings.solver.up.active)
    
    if @next?
      @labels.down.show().attr 'y', @y + Group.margin + Group.height/2 + 16
      @renderCrossings "down"
      @arrows.down.toggleClass('computing', @crossings.solver.down.active)
      @arrows.down.show().node.setAttribute "d", arrowPath(Group.margin, @y + Group.margin + Group.height/2 + 5 - Session.buttonHeight/2, Session.buttonWidth, Session.buttonHeight, Session.buttonTip, 1)
      
    group.draw() for group in this
    @dirty = false
    @previous.draw() if @previous?
    @next.draw()     if @next?

class Sessions extends Container
  constructor: (@root) ->
  
  draw: ->
    session.draw() for session in this

class Person extends Array
  @mixin Sync
  
  @selected = null
  
  constructor: (@id) ->
    @above   = []
    @current = []
    
    @property "dirty", (dirty) ->
      mark.dirty = true for mark in this
    
    @property "highlighted", (highlighted) ->
      @dirty = true
      @shape.toggleClass 'highlighted', highlighted
    
    @property "active", (active) ->
      Person.selected = if active then this else null
      @dirty = true
      @shape.toggleClass 'highlighted', (active or @highlighted)
      mark.active = active for mark in this
    
    @shape = paper.path("M0 0")
                    .addClass('edge')
                    .mouseover(@over)
                    .mouseout(@out)
  over: =>
    @active = true
    @draw()
    
  out : =>
    @active = false
    @draw()
  
  push: (mark) ->
    mark.shape.mouseover(@over).mouseout(@out)
    super(mark)
  
  draw: ->
    return unless @dirty
    @shape.node.setAttribute "d", (mark.path() for mark in this).join()
    @shape.toFront()
    @dirty = false
    
    for mark in this
      mark.draw()
      mark.shape.toFront()
  
  move: (dir) ->
    appearedIn = {}
    for mark in this
      return if mark.container.container.index of appearedIn
      appearedIn[mark.container.container.index] = true
    
    for mark in this
      if dir is "left"
        mark.container.move(mark, 0)
      else
        mark.container.move(mark, mark.container.length - 1)
      mark.update()
    
    for mark in this
      for other in mark.container
        other.update()
    
    for mark in this
      for other in mark.container
        other.person.draw()
    
    @draw()

class Data
  constructor: (sessions) ->
    @sessions = new Sessions(this)
    @persons  = {}
    
    for groups in sessions
      for members in groups
        for id in members
          unless @persons[id]
            person = new Person id
            @persons[id] =  person 
            person.root = this
    
    for groups, sid in sessions
      session = @sessions.push new Session
      for members, gid in groups
        group = session.push new Group
        for id, mid in members
          person = @persons[id]
          
          mark   = group.push new Mark person
          person.push mark
          
          person.current.push(mark)
          for parent in person.above
            edge = new Edge parent, mark
            parent.push edge
            mark.push   edge
      
      for _, person of @persons
        person.above   = person.current
        person.current = []
    
    @updateCrossings = true
    @draw()
    
  draw: ->
    @sessions.draw()
    person.draw() for person in @persons
  
  export: ->
    outSessions = []
    for session in @sessions
      outSessions.push(outSession = [])
      for group in session
        outSession.push(outGroup = [])
        for mark in group
          outGroup.push(mark.person.id)
    return JSON.stringify(outSessions)

jQuery ->
  data = if (dataStr = window.localStorage.getItem("data"))? then JSON.parse(dataStr) else window.data
  lastSaved = window.localStorage.getItem("save-date")
  
  $('#save-date').text("last saved: #{lastSaved}") if lastSaved?
  
  window.paper = Raphael(0, 0, 900, Session.height*data.length)
  
  # Bindings
  ## Saving
  save = ->
    return if $('#save').attr('disabled') is "disabled"
    $('#save').attr('disabled', true)
    window.localStorage.setItem('data', dataRoot.export())
    
    
    now = new Date
    lastSaved = "#{now.getDate()}/#{1+now.getMonth()}/#{now.getFullYear()} @ #{now.getHours()}:#{now.getMinutes()}"
    window.localStorage.setItem('save-date', lastSaved)
    setTimeout (-> 
      $('#save').attr('disabled', false)
      $('#save-date').text("last saved: #{lastSaved}")
    ), 1000
  
  $save    = $('#save').click(save)
  $('#download').click ->
    window.open 'data:application/javascript,' +encodeURIComponent """
    /* 
      save as data.js and replace old version with this one 
    */
    
    data = #{dataRoot.export()};
    """
  
  ## Keyboard controls
  # start/stop untanglers
  move = (dir) ->
    return unless Person.selected?
    Person.selected.move(dir)
  
  $(document).keypress (e) ->
    key = String.fromCharCode(e.which)
    if key == "w"
      move 'left'
      return false
    
    if key == "x"
      move "right"
      return false
    
    return true unless Group.selected?
    
    bindings =
      a: Session.selected.crossings.solver.up
      q: Session.selected.crossings.solver.down
      z: Group.selected.crossings.local.solver.up
      s: Group.selected.crossings.local.solver.down
      e: Group.selected.crossings.global.solver.up
      d: Group.selected.crossings.global.solver.down
    
    return true unless key of bindings
    
    bindings[key].toggle()
    return false
  
  for type in ['local', 'global']
    for dir in ['down', 'up']
      do (type, dir) ->
        $("##{type}-#{dir}-toggle").click ->
          return false unless Group.selected
          Group.selected.crossings[type].solver[dir].toggle()
          return false
  # motion
  meta = false
  $(document).keydown (e) ->
    # save : meta+s
    if meta == true and e.which == 83
      save()
      return false
    return meta = true if e.metaKey
    
    meta = false
    return true unless 37 <= e.which <= 40 or e.which == 27
    
    # if nothing is selected, select first group of first session
    unless Group.selected?
      Group.select(dataRoot.sessions[0][0])
      return false
    
    # ESC : unselect
    if e.which == 27
      Group.select(null)
      return false
    
    group   = Group.selected
    session = Session.selected
    
    if e.which is 37
      Group.select if group.previous? then group.previous else session[session.length - 1]
      return false
    
    if e.which is 39
      Group.select if group.next? then group.next else session[0]
      return false
    
    dir = {38: "previous", 40: "next"}[e.which]
    
    if session[dir]?
      distance = (g1, g2) -> Math.abs(g1.x + g1.width/2 - g2.x - g2.width/2)
      
      closest  = session[dir][0]
      minimum  = distance(group, closest)
      
      for other in session[dir]
        if (d = distance(group, other)) < minimum
          minimum = d
          closest = other
      Group.select closest
    
    return false
  
  window.dataRoot = new Data(data)
  $('#loading').hide()
  $save.attr('disabled', false)