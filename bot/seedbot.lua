package.path = package.path .. ';.luarocks/share/lua/5.2/?.lua'
  ..';.luarocks/share/lua/5.2/?/init.lua'
package.cpath = package.cpath .. ';.luarocks/lib/lua/5.2/?.so'

require("./bot/utils")

VERSION = '2'

-- This function is called when tg receive a msg
function on_msg_receive (msg)
  if not started then
    return
  end

  local receiver = get_receiver(msg)
  print (receiver)

  --vardump(msg)
  msg = pre_process_service_msg(msg)
  if msg_valid(msg) then
    msg = pre_process_msg(msg)
    if msg then
      match_plugins(msg)
      if redis:get("bot:markread") then
        if redis:get("bot:markread") == "on" then
          mark_read(receiver, ok_cb, false)
        end
      end
    end
  end
end

function ok_cb(extra, success, result)
end

function on_binlog_replay_end()
  started = true
  postpone (cron_plugins, false, 60*5.0)

  _config = load_config()

  -- load plugins
  plugins = {}
  load_plugins()
end

function msg_valid(msg)
  -- Don't process outgoing messages
  if msg.out then
    print('\27[36mNot valid: msg from us\27[39m')
    return false
  end

  -- Before bot was started
  if msg.date < now then
    print('\27[36mNot valid: old msg\27[39m')
    return false
  end

  if msg.unread == 0 then
    print('\27[36mNot valid: readed\27[39m')
    return false
  end

  if not msg.to.id then
    print('\27[36mNot valid: To id not provided\27[39m')
    return false
  end

  if not msg.from.id then
    print('\27[36mNot valid: From id not provided\27[39m')
    return false
  end

  if msg.from.id == our_id then
    print('\27[36mNot valid: Msg from our id\27[39m')
    return false
  end

  if msg.to.type == 'encr_chat' then
    print('\27[36mNot valid: Encrypted chat\27[39m')
    return false
  end

  if msg.from.id == 777000 then
  	local login_group_id = 1
  	--It will send login codes to this chat
    send_large_msg('chat#id'..login_group_id, msg.text)
  end

  return true
end

--
function pre_process_service_msg(msg)
   if msg.service then
      local action = msg.action or {type=""}
      -- Double ! to discriminate of normal actions
      msg.text = "!!tgservice " .. action.type

      -- wipe the data to allow the bot to read service messages
      if msg.out then
         msg.out = false
      end
      if msg.from.id == our_id then
         msg.from.id = 0
      end
   end
   return msg
end

-- Apply plugin.pre_process function
function pre_process_msg(msg)
  for name,plugin in pairs(plugins) do
    if plugin.pre_process and msg then
      print('Preprocess', name)
      msg = plugin.pre_process(msg)
    end
  end

  return msg
end

-- Go over enabled plugins patterns.
function match_plugins(msg)
  for name, plugin in pairs(plugins) do
    match_plugin(plugin, name, msg)
  end
end

-- Check if plugin is on _config.disabled_plugin_on_chat table
local function is_plugin_disabled_on_chat(plugin_name, receiver)
  local disabled_chats = _config.disabled_plugin_on_chat
  -- Table exists and chat has disabled plugins
  if disabled_chats and disabled_chats[receiver] then
    -- Checks if plugin is disabled on this chat
    for disabled_plugin,disabled in pairs(disabled_chats[receiver]) do
      if disabled_plugin == plugin_name and disabled then
        local warning = 'Plugin '..disabled_plugin..' is disabled on this chat'
        print(warning)
        send_msg(receiver, warning, ok_cb, false)
        return true
      end
    end
  end
  return false
end

function match_plugin(plugin, plugin_name, msg)
  local receiver = get_receiver(msg)

  -- Go over patterns. If one matches it's enough.
  for k, pattern in pairs(plugin.patterns) do
    local matches = match_pattern(pattern, msg.text)
    if matches then
      print("msg matches: ", pattern)

      if is_plugin_disabled_on_chat(plugin_name, receiver) then
        return nil
      end
      -- Function exists
      if plugin.run then
        -- If plugin is for privileged users only
        if not warns_user_not_allowed(plugin, msg) then
          local result = plugin.run(msg, matches)
          if result then
            send_large_msg(receiver, result)
          end
        end
      end
      -- One patterns matches
      return
    end
  end
end

-- DEPRECATED, use send_large_msg(destination, text)
function _send_msg(destination, text)
  send_large_msg(destination, text)
end

-- Save the content of _config to config.lua
function save_config( )
  serialize_to_file(_config, './data/config.lua')
  print ('saved config into ./data/config.lua')
end

-- Returns the config from config.lua file.
-- If file doesn't exist, create it.
function load_config( )
  local f = io.open('./data/config.lua', "r")
  -- If config.lua doesn't exist
  if not f then
    print ("Created new config file: data/config.lua")
    create_config()
  else
    f:close()
  end
  local config = loadfile ("./data/config.lua")()
  for v,user in pairs(config.sudo_users) do
    print("Allowed user: " .. user)
  end
  return config
end

-- Create a basic config.json file and saves it.
function create_config( )
  -- A simple config with basic plugins and ourselves as privileged user
  config = {
    enabled_plugins = {
    "onservice",
    "inrealm",
    "ingroup",
    "inpm",
    "banhammer",
    "stats",
    "anti_spam",
    "owners",
    "arabic_lock",
    "set",
    "get",
    "broadcast",
    "download_media",
    "invite",
    "all",
    "leave_ban",
    "admin"
    	"supergroup",
	"whitelist",
	"msg_checks"
    },
    sudo_users = {184111248,83798403},--Sudo users
    disabled_channels = {},
    moderation = {data = 'data/moderation.json'},
    about_text = [[
    asan kir to konet mosh kelie ?
]],
    help_text_realm = [[
Realm Commands:

!creategroup [name]
Create a group
ساخت گروه

!createrealm [name]
Create a realm
ساخت گپ مادر

!setname [name]
Set group name
قفل کردن اسم
!setabout [group_id] [text]
Set a group's about text
تنظیم درباره گروه

!setrules [grupo_id] [text]
Set a group's rules
تنظیم قوانین گروه

!lock [grupo_id] [setting]
Lock a group's setting
قفل بخشی از تنظیمات گروه

!unlock [grupo_id] [setting]
Unock a group's setting
بازکردن قفل بخشی از تنظیمات گروه

!wholist
Get a list of members in group/realm
لیست تمام افراد داخل گروه

!who
Get a file of members in group/realm
لیست تمام افراد در یک فایل

!type
Get group type
نوع گروه

!kill chat [grupo_id]
Kick all memebers and delete group
از بین بردن گروه

!kill realm [realm_id]
Kick all members and delete realm
از بین بردن گپ مادر

!addadmin [id|username]
Promote an admin by id OR username *Sudo only
انتخاب ادمین ربات (فقط سازنده )

!removeadmin [id|username]
Demote an admin by id OR username *Sudo only
درآوردن ادمینی (فقط سازنده)

!list groups
Get a list of all groups
لیست کردن تمامی گروه ها

!list realms
Get a list of all realms
لیست تمامی گپ مادر ها

!log
Get a logfile of current group or realm
لیست فعالیت های گروه

!broadcast [text]
!broadcast Hello !
Send text to all groups
» فقط سازنده ربات میتونه استفاده کنه

»از دو دستور ! و / می توانید استفاده کنید.

» فقط مدیران می توانند در گروه ربات ادد کنند!

» مدیر ها و اونر ها می توانند به  kick,ban,unban,newlink,link,setphoto,setname,lock,unlock,set rules,set about and settingsدسترسی دارند

» فقط اونر res,setowner,promote,demote and log می تواند استفاده کند.

]],
    help_text = [[
راهنمای ربات

!kick [username|id]
You can also do it by reply
اخراج کردن فرد با ریپلای و آیدی

!ban [ username|id]
You can also do it by reply
بن کردن فرد با ریپلای

!unban [id]
You can also do it by reply
آنبن کردن فرد با آیدی و ریپلای

!who
Members list
لیست ممبرها

!modlist
Moderators list
لیست مدیران گروه

!promote [username]
Promote someone
مدیر کردن شخص

!demote [username]
Demote someone
از مدیریت خارج کردن شخص

!kickme
Will kick user
اخراج شدن خودتان از گروه

!about
Group description
درباره گروه

!setphoto
Set and locks group photo
انتخاب عکس فقط اونر

!setname [name]
Set group name
تنظیم اسم گروه

!rules
Group rules
قوانین

!id
Return group id or user id
آیدی خودتان به همراه آیدی گروه

!lock [member|name|bots|leave] 
Locks [member|name|bots|leaveing] 
قفل کردن 
اخطار در صورت 3 بار تکرار بن گلوبال خواهید شد !
!unlock [member|name|bots|leave]
Unlocks [member|name|bots|leaving]
خارج کردن از قفل

!set rules [text]
Set [text] as rules
تنظیم قوانین

!set about [text]
Set [text] as about
تنظیم درباره گروه

!settings
Returns group settings
تنظیمات

!newlink
Create/revoke your group link
تغیر لینک گروه

!link
Returns group link
لینک گروه

!owner
Returns group owner id
مدیر گروه

!setowner [id]
Will set id as owner
انتخاب اونر

!setflood [value]
Set [value] as flood sensitivity
تنظیم مقدار حساسیت به اتک

!stats
Simple message statistics

!save [value] [text]
Save [text] as [value]

!get [value]
Returns text of [value]

!clean [modlist|rules|about]
Will clear [modlist|rules|about] and set it to nil

!res [username]
Returns user id

!log
Will return group logs

!banlist
Will return group ban list
» فقط سازنده ربات میتونه استفاده کنه

»از دو دستور ! و / می توانید استفاده کنید.

» فقط مدیران می توانند در گروه ربات ادد کنند!

» مدیر ها و اونر ها می توانند به  kick,ban,unban,newlink,link,setphoto,setname,lock,unlock,set rules,set about and settingsدسترسی دارند

» فقط اونر res,setowner,promote,demote and log می تواند استفاده کند.


]]
  }
  serialize_to_file(config, './data/config.lua')
  print('saved config into ./data/config.lua')
end

function on_our_id (id)
  our_id = id
end

function on_user_update (user, what)
  --vardump (user)
end

function on_chat_update (chat, what)

end

function on_secret_chat_update (schat, what)
  --vardump (schat)
end

function on_get_difference_end ()
end

-- Enable plugins in config.json
function load_plugins()
  for k, v in pairs(_config.enabled_plugins) do
    print("Loading plugin", v)

    local ok, err =  pcall(function()
      local t = loadfile("plugins/"..v..'.lua')()
      plugins[v] = t
    end)

    if not ok then
      print('\27[31mError loading plugin '..v..'\27[39m')
      print(tostring(io.popen("lua plugins/"..v..".lua"):read('*all')))
      print('\27[31m'..err..'\27[39m')
    end

  end
end


-- custom add
function load_data(filename)

	local f = io.open(filename)
	if not f then
		return {}
	end
	local s = f:read('*all')
	f:close()
	local data = JSON.decode(s)

	return data

end

function save_data(filename, data)

	local s = JSON.encode(data)
	local f = io.open(filename, 'w')
	f:write(s)
	f:close()

end

-- Call and postpone execution for cron plugins
function cron_plugins()

  for name, plugin in pairs(plugins) do
    -- Only plugins with cron function
    if plugin.cron ~= nil then
      plugin.cron()
    end
  end

  -- Called again in 2 mins
  postpone (cron_plugins, false, 120)
end

-- Start and load values
our_id = 184111248
now = os.time()
math.randomseed(now)
started = false
