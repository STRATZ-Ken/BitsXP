require('luau')

UI = {
  settings = 0,
  jobInfo = {
    level = 0,
    primaryJob = '',
    secondaryJob = '',
  },
  xp = {
    current = 0,
    max = 0,
    remaining = 0,
  },
  merit = {
    limit_points = 0,
	merit_points = 0,
    remaining = 0,
    max = 0,
  },
  session = {
    startTime = nil,
    xpEarned = 0,
    xpRatePerSecond = 0,
    xpRatePerHour = 0,
    estimatedTimeToLevelSeconds = 0,
    nextChain = {
      number = 0,
      deadline = nil,
    },
  },
  nextChainTimeout = 0,
  chainNo = 0,
  maxChain = 0,
}

local frameCount = 0
local box = nil

local default_chain_timers = {
  { maxLevel = 10,  timers = {  80,  80,  60,  40,  30,  15 } },
  { maxLevel = 20,  timers = { 130, 130, 110,  80,  60,  25 } },
  { maxLevel = 30,  timers = { 160, 150, 120,  90,  60,  30 } },
  { maxLevel = 40,  timers = { 200, 200, 170, 130,  80,  40 } },
  { maxLevel = 50,  timers = { 290, 290, 230, 170, 110,  50 } },
  { maxLevel = 999, timers = { 300, 300, 240, 180, 120,  60 } },
}

function setupUI()
  if box ~= nil then
    return
  end
  

  box = texts.new('${current_string}', settings.textBox, settings)
  box.current_string = ''
  windower.register_event('prerender', handleUIPrerender)
  windower.register_event('outgoing chunk', processOutgoingDataChunk)
  windower.register_event('incoming chunk', processIncomingDataChunk)
  windower.register_event('gain experience', processStuff)
  
  if settings.visible then
    box:show()
  end
end

function handleUIPrerender()
  if (frameCount % 30 == 0) and box:visible() then
    updateUI()
  end

  frameCount = frameCount + 1
end

function processOutgoingDataChunk(id, data, modified, isInjected, isBlocked)
  if isInjected then
    return
  end

  local packetTable = packets.parse('outgoing', data)

  if id == 0x074 then
    if packetTable['Join'] and settings.resetOnPartyAccept then
      print('[BitsXP] Automatically clearing session XP...')
      clearUISession()
    end
  end

end

function processStuff(amount, chain_number, limit)
  time = os.time()
  if chain_number > 0 or UI.nextChainTimeout < time then
    UI.chainNo = chain_number
    UI.nextChainTimeout = time + getNextChainTime()
    if UI.chainNo > UI.maxChain then
      UI.maxChain = UI.chainNo
    end
  end
end

function getNextChainTime()
  local playerLevel = windower.ffxi.get_player().main_job_level
  local timers = getMatchingLevelTimers(playerLevel)

  local nextChain = UI.chainNo + 1
  if nextChain > #timers then
      nextChain = #timers
  end

  return timers[nextChain]
end

function getMatchingLevelTimers(mobLevel)
  for _, v in ipairs(default_chain_timers) do
      if mobLevel < v.maxLevel then
          return v.timers
      end
  end
  return chain_timers[-1]
end

function processIncomingDataChunk(id, data, modified, isInjected, isBlocked)
  if isInjected then
    return
  end

  local packetTable = packets.parse('incoming', data)

  if id == 0x2D then
    if 
		packetTable['Message'] == 8 or packetTable['Message'] == 108 or packetTable['Message'] == 253 or
		packetTable['Message'] == 371 or packetTable['Message'] == 372
	then
      -- player gained experience points
      addExperiencePoints(packetTable['Param 1'], (packetTable['Message'] == 371 or packetTable['Message'] == 372))
    end
  elseif id == 0x61 then
    --UI.xp.current = packetTable['Current EXP']
    --UI.xp.max = packetTable['Required EXP']
	  UI.xp.current = data:unpack('H',0x11)
	  UI.xp.max = data:unpack('H',0x13)
    UI.xp.remaining = UI.xp.max - UI.xp.current
  elseif id == 0x63 and packetTable['Order'] == 2 then
    --UI.xp.current = packetTable['Current EXP']
    --UI.xp.max = packetTable['Required EXP']
	  UI.merit.limit_points = packetTable['Limit Points']
	  UI.merit.merit_points = packetTable['Merit Points']
	  UI.merit.max = packetTable['Max Merit Points']
	UI.merit.remaining = 10000 - UI.merit.limit_points 
  elseif id == 0xB and box:visible() then
    box:hide()
  elseif id == 0xA and settings.visible then
    box:show()
  end
end

function updateUI()
  -- Lv. 24 NIN/WAR
  -- XP: 234 / 1,321
  -- TNL: 834
  -- XP/hr: 15.7k
  -- ETL: 1h26m30s
  -- [Next chain #3: 1m27s left]

  -- first, update xp rates
  updateXPRate()

  local info = windower.ffxi.get_player()
  if not info then return '' 
  end 
  local 
  string = ' '..buildJobLabel(info)..white(' | ')
  if (info.main_job_level ~= 75) and (UI.xp.current ~= 43999) then
	string = string..buildXPLabel()..white(' | ')
  else
	string = string..buildMeritPoints()..white(' | ')
  end
  if info.main_job_level ~= 75 and UI.xp.current ~= 43999 then
	string = string..buildTNLLabel()..white(' | ') 
  else
	string = string..buildTNMLabel()..white(' | ')
  end
  string = string..buildXPPerHourLabel()..white(' | ')
  if info.main_job_level ~= 75 and UI.xp.current ~= 43999 then
	string = string..buildEstimatedTimeToLevelLabel()..white(' | ')
  else
    string = string..buildEstimatedTimeToMeritLabel()..white(' | ')
  end
  string = string..buildNextChainLabel()

  box.current_string = string..' '
end

function buildJobLabel(info)
  local level = info.main_job_level
  local slevel = info.sub_job_level
  local pJob = string.upper(info.main_job)
  local sJob = (info.sub_job and string.upper(info.sub_job))
  local ssJob = (info.sub_job_level and string.upper(info.sub_job_level))

  return white('Lv. '..pJob..''..level..'/'..sJob..''..slevel)
end

function buildXPLabel()
  return white('XP: '..ice(commaValue(UI.xp.current)..'/'..commaValue(UI.xp.max)))
end

function buildTNLLabel()
  return white('TNL: '..ice(commaValue(UI.xp.remaining)))
end

function buildTNMLabel()
  return white('TNM: '..ice(commaValue(UI.merit.remaining)))
end

function buildXPPerHourLabel()
  local xphr = UI.session.xpRatePerHour

  if xphr < 5 then
    xphr = red(xphr)
  elseif xphr >= 5 and xphr < 10 then
    xphr = yellow(xphr)
  elseif xphr >= 10 then
    xphr = green(xphr)
  end

  return white('XP/hr: '..xphr..'k')
end


function buildMeritPoints()
  return white('Merit: '..UI.merit.merit_points..'/'..UI.merit.max)
end

function buildEstimatedTimeToLevelLabel()
  return white('ETL: '..ice(calculateTimeToLevel()))
end

function buildEstimatedTimeToMeritLabel()
  return white('ETM: '..ice(calculateTimeToMerit()))
end

function buildNextChainLabel()
  local time = os.time()
  local chainTimer = UI.nextChainTimeout - time
  if chainTimer > 0 then
    local nextChain = UI.chainNo + 1
    return 'Next Chain #'..ice(nextChain)..white(' has ')..ice(calculateTimeLeftForNextChain(chainTimer))..white(' left')
  end
  
  return ''
end

function sessionIsOnChain()
  return UI.session.nextChain.number > 0
end

function calculateTimeToLevel()
  return formatTime(UI.session.estimatedTimeToLevelSeconds)
end

function calculateTimeToMerit()
  return formatTime(UI.session.estimatedTimeToMeritSeconds)
end

function calculateTimeLeftForNextChain(timeInSeconds)
  if (timeInSeconds == nil or timeInSeconds == 0) then
      return "N/A"
  end
  local seconds = timeInSeconds % 60
  local minutes = math.floor(timeInSeconds / 60) % 60
  local hours = math.floor(timeInSeconds / 60 / 60)
  local result = ""
  if hours > 0 then
      result = result .. string.format("%dh", hours)
  end
  if minutes > 0 then
      result = result .. string.format("%dm", minutes)
  end
  if seconds > 0 then
      result = result .. string.format("%ds", seconds)
  end
  return result
end

function addExperiencePoints(experienceGained, is_merit)
  -- start the session if it's not started
  if UI.session.startTime == nil then
    UI.session.startTime = os.time()
    print('[BitsXP] Starting XP Session...')
  end

  -- add the exp to the session
  UI.session.xpEarned = UI.session.xpEarned + experienceGained

  -- also, add the exp to the character info
  if is_merit then
	UI.merit.limit_points = UI.merit.limit_points + experienceGained
  else
	UI.xp.current = UI.xp.current + experienceGained
	if UI.xp.current > UI.xp.remaining then
	  UI.xp.current = UI.xp.current - UI.xp.remaining
	end
  end
end

function updateXPRate()
  local startTime = UI.session.startTime
  if startTime == nil then
    startTime = os.time()
  end

  local timeElapsed = os.time() - startTime

  if timeElapsed == 0 or UI.session.xpEarned == 0 then
    return
  end

  UI.session.xpRatePerSecond = (UI.session.xpEarned / timeElapsed)
  UI.session.xpRatePerHour = round(UI.session.xpRatePerSecond * 3.6, 1)
  UI.session.estimatedTimeToLevelSeconds = math.floor(UI.xp.remaining / UI.session.xpRatePerSecond)
  UI.session.estimatedTimeToMeritSeconds = math.floor(UI.merit.remaining / UI.session.xpRatePerSecond)

  -- update max xp
  UI.xp.max = (UI.xp.current + UI.xp.remaining)
end

function clearUISession()
  UI.session.startTime = nil
  UI.session.xpEarned = 0
  UI.session.xpRatePerSecond = 0
  UI.session.xpRatePerHour = 0
  UI.session.estimatedTimeToLevelSeconds = 0
  UI.session.estimatedTimeToMeritSeconds = 0
  UI.session.nextChain = {
    number = 0,
    deadline = nil,
  }
end

function toggleUIVisibility()
  if settings.visible then
    settings.visible = false
    box:hide()
  else
    settings.visible = true
    box:show()
  end

  config.save(settings)
end
