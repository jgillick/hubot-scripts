# Description:
#   Allows Hubot to store a recent chat history for services like IRC that
#   won't do it for you. View the history within the chat window or from the http server
#   at /history.
#
# Dependencies:
#   "moment": "2.1.0"
#
# Configuration:
#   HUBOT_HISTORY_LINES
#
# Commands:
#   hubot show [<lines> lines of] history - Shows <lines> of history, otherwise all history
#   hubot clear history - Clears the history
#
# Author:
#   wubr

moment = require("moment")
querystring = require('querystring')

class History
  constructor: (@robot, @keep) ->
    @cache = []
    @robot.brain.on 'loaded', =>
      if @robot.brain.data.history
        @robot.logger.info "Loading saved chat history"
        @cache = @robot.brain.data.history

  add: (message) ->
    @cache.push message
    while @cache.length > @keep
      @cache.shift()
    @robot.brain.data.history = @cache

  show: (lines) ->
    if (lines > @cache.length)
      lines = @cache.length
    reply = 'Showing ' + lines + ' lines of history:\n'
    reply = reply + @entryToString(message) + '\n' for message in @cache[-lines..].reverse()
    return reply

  clear: ->
    @cache = []
    @robot.brain.data.history = @cache

  entryToString: (event) ->
    return "[#{event.hours}:#{event.minutes}] \##{event.room} <#{event.user}>: #{event.message}"

class HistoryEntry
  constructor: (@user, @message, @room) ->
    @time = new Date()
    @hours = @time.getHours()
    @minutes = @time.getMinutes()
    if @minutes < 10
      @minutes = '0' + @minutes

module.exports = (robot) ->

  options =
    lines_to_keep:  process.env.HUBOT_HISTORY_LINES

  unless options.lines_to_keep
    options.lines_to_keep = 500

  history = new History(robot, options.lines_to_keep)

  # Log history
  robot.hear /(.*)/i, (msg) ->
    if msg.match[1] != ''
      user = msg.message.user
      room = msg.message.room
      historyentry = new HistoryEntry(user.name, msg.match[1], room)
      history.add historyentry

  # Show history
  robot.respond /show ((\d+) lines of )?history/i, (msg) ->
    if msg.match[2]
      lines = msg.match[2]
    else
      lines = history.keep
    msg.send history.show(lines)

  # Clear history
  robot.respond /clear history/i, (msg) ->
    msg.send "Ok, I'm clearing the history."
    history.clear()

  # Show history HTML
  robot.router.get '/history', (req, res) ->
    query = querystring.parse(req._parsedUrl.query)
    res.setHeader( 'content-type', 'text/html' );

    lines = history.cache.length
    listHtml = '';
    longestName = 5;

    # Room
    room = query.room
    roomTitle = "all rooms"
    if room
      roomTitle = room

    #
    # Build list HTML
    #
    oddEven = -1
    lastUser = false
    for i in [history.cache.length - 1..0] by -1
      message = history.cache[i]
      time = moment(message.time).fromNow()

      # Is this the same user as the last row
      sameUser = (lastUser == message.user)

      # From the correct room?
      if room and room != message.room
        continue

      # Format message text
      text = message.message
      text = text.replace(/(https?:\/\/.*?)(\s|$)/ig, '<a href="$1" target="_blank">$1</a>$2') # link URLs

      # Room HTML line (only show if you're not viewing a specific room)
      roomEncoded = encodeURIComponent(message.room)
      roomHtmlLink = ""
      if !room
        if !message.room
          roomHtmlLink = "<span class='room to-bot'>#{robot.name}</span>"
        else
          roomHtmlLink = "<span class='room'><a href='/history/?room=#{roomEncoded}''>#{message.room}</a></span>"


      # Zebra rows
      if !sameUser
        oddEven *= -1;
      className = if (oddEven == 1) then "odd" else "even"

      # Don't include duplicate user
      userHTML = ""
      if !sameUser
        userHTML = "<dt class='#{className}''>#{message.user}</dt>"

      # List
      listHtml += """
      #{userHTML}
      <dd class="#{className}">
        <time datetime="#{message.time}">#{time}</time>
        #{roomHtmlLink}
        <span class="message">#{text}</span>
      </dd>
      """

      # Longest user name
      if message.user.length > longestName and message.user.length < 15
        longestName = message.user.length

      lastUser = message.user;
    #
    # Build entire HTML page
    #
    html = """
<!DOCTYPE html>
<head>
  <title>Hubot Transcript</title>
  <style type="text/css">
    body {
      background: #d3d6d9;
      color: #636c75;
      text-shadow: 0 1px 1px rgba(255, 255, 255, .5);
      font-family: Helvetica, Arial, sans-serif;
    }
    a {
      color: #486F96;
    }
    a:hover {
      color: #965148;
    }
    h1 {
      margin: 8px 0;
      padding: 0;
    }

    /* Mobile styles */
    dt {
      font-weight: bold;
      padding: 3px 5px;
      margin: 5px 0 0;
      font-family: courier;
      white-space: nowrap;
      background: #BDBDBD;
    }
    dd {
      margin: 3px 0 0 10px;
      padding: 3px 0 3px 3px;
    }
    dd time {
      margin: -2em 0 0 #{longestName}em;
      padding-left: 10px;
      font-style: italic;
      font-size: 12px;
      display: block;
    }
    dd .room {
      font-size: 12px;
      margin: -1.3em 5px 0 0;
      float: right;
    }
    dd .message {
      display: block;
      clear: both;
      margin-top: 3px;
    }
    dd .room:before {
      content: 'in ';
    }
    dd .room.to-bot:before {
      content: 'to ';
    }

    /* Only show the first time/room for a user's list of messages, for mobile */
    dt ~ dd time,
    dt ~ dd .room {
      display: none;
    }
    dt + dd time,
    dt + dd .room {
      display: block;
    }

    /* Desktop styles */
    @media (min-width: 650px) {
      dt {
        float: left;
        clear: both;
        width: #{longestName}em;
        overflow: hidden;
        text-align: right;
        font-weight: bold;
        padding: 3px 0;
        margin: 0;
        font-family: courier;
        background: transparent;
      }
      dt:after {
        content: ':';
        padding: 0 3px 0 0;
      }
      dd {
        margin: 0 0 0 #{longestName}em;
        padding: 3px 0 3px 3px;
        border-bottom: 1px solid #B5BBC0;
      }
      dd time {
        margin: 3px 0;
        padding: 0;
        float: left;
        display: inline-block !important;
      }
      dd .room {
        margin: 0 5px;
        float: none;
        display: inline-block !important;
      }
    }
  </style>
</head>
<body>

<h1>Hubot transcripts for #{roomTitle}</h1>

<dl>
  #{listHtml}
</dl>
</body>
</html>
    """

    res.end html