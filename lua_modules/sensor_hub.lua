--[[
sensor_hub.lua for ESP8266 with nodemcu-firmware
  Read atmospheric (ambient) temperature, relative humidity and pressure
  from BMP085/BMP180 and AM2320/AM2321 sensors, and particulate matter
  from a PMS3003.
  More info at  https://github.com/avaldebe/AQmon

Written by Álvaro Valdebenito.

MIT license, http://opensource.org/licenses/MIT
]]

local M = {name=...}
_G[M.name] = M

-- Format module outputs
function M.format(vars,message,squeese)
  local k,v
  for k,v in pairs(vars) do
-- formatted output (w/padding) from integer values
    if type(v)=='number' then
      if k=='pm01' or k=='pm25' or k=='pm10' then
        M[k]=('%4d'):format(v)
      elseif k=='t' or k=='temperature' then  -- t/10 --> %5.1f
        v=('%4d'):format(v)
        M.t=('%3s.%1s'):format(v:sub(1,3),v:sub(4))
      elseif k=='h' or k=='humidity' then     -- h/10 --> %5.1f
        v=('%4d'):format(v)
        M.h=('%3s.%1s'):format(v:sub(1,3),v:sub(4))
      elseif k=='p' or k=='pressure' then      -- p/100 --> %7.2f
        v=('%6d'):format(v)
        M.p=('%4s.%2s'):format(v:sub(1,4),v:sub(5))
      elseif k=='upTime' then                 -- days:hh:mm:ss
        M[k]=('%02d:%02d:%02d:%02d')
            :format(v/86400,v%86400/3600,v%3600/60,v%60)
      else                                    -- heap|time|*
        M[k]=('%d'):format(v)
      end
-- formatted output (w/padding) default values ('null')
    elseif type(v)=='string' then
      if v=='' then v='null' end
      if k=='pm01' or k=='pm25' or k=='pm10' then
        M[k]=('%4s'):format(v)
      elseif k=='t' or k=='h' then
        M[k]=('%5s'):format(v)
      elseif k=='p' then
        M[k]=('%7s'):format(v)
      end
    end
  end

-- process message for csv/column output
  if type(message)=='string' and message~='' then
    local payload=message:gsub('{(.-)}',M)
    M.upTime,M.time,M.heap=nil,nil,nil  -- release memory
    if squeese then                     -- remove all spaces (and padding)
      payload=payload:gsub(' ','')      --   from output
    end
    return payload
  end
end

local SDA,SCL,PMset     -- buffer pinout
local cleanup=false     -- release modules after use
local persistence=false -- use last values when read fails
local init=false
function M.init(sda,scl,pm_set,lowHeap,keepVal)
-- Output variables (padded for csv/column output)
  M.format({p='',h='',t='',pm01='',pm25='',pm10=''})
  if init then return end

  if type(sda)=='number' then SDA=sda end
  if type(scl)=='number' then SCL=scl end
  if type(pm_set)=='number' then PMset=pm_set end
  if type(lowHeap)=='boolean' then cleanup=lowHeap     end
  if type(keepVal)=='boolean' then persistence=keepVal end

  assert(type(SDA)=='number',
    ('%s.init %s argument sould be %s'):format(M.name,'1st','SDA'))
  assert(type(SCL)=='number',
    ('%s.init %s argument sould be %s'):format(M.name,'2nd','SCL'))
  assert(type(PMset)=='number' or PMset==nil,
    ('%s.init %s argument sould be %s'):format(M.name,'3rd','PMset'))

  require('pms3003').init(PMset)
  if cleanup then  -- release memory
    pms3003,package.loaded.pms3003=nil,nil
  end
  init=true
end

function M.read(verbose,callBack)
-- ensure module is initialized
  assert(init,('Need %s.init(...) before %s.read(...)'):format(M.name,M.name))
-- check input varables
  assert(type(verbose)=='boolean' or verbose==nil,
    ('%s.init %s argument should be %s'):format(M.name,'1st','boolean'))
  assert(type(callBack)=='function' or callBack==nil,
    ('%s.init %s argument should be %s'):format(M.name,'2nd','function'))

-- reset output
  if not persistence then M.init() end
-- verbose print: csv/column output
  local payload='%s:{time}[s],{t}[C],{h}[%%],{p}[hPa],{pm01},{pm25},{pm10}[ug/m3],{heap}[b]'
  local sensor -- local "name" for sensor module

  sensor=require('bmp180')
  if sensor.init(SDA,SCL) then
    sensor.read(0)   -- 0:low power .. 3:oversample
    if verbose then
      sensor.heap,sensor.time=node.heap(),tmr.time()
      print(M.format(sensor,payload:format(sensor.name)))
    else
      M.format(sensor)
    end
  elseif verbose then
    print(('--Sensor "%s" not found!'):format(sensor.name))
  end
  if cleanup then  -- release memory
    _G[sensor.name],package.loaded[sensor.name],sensor=nil,nil,nil
  end

  sensor=require('am2321')
  if sensor.init(SDA,SCL) then
    sensor.read()
    if verbose then
      sensor.heap,sensor.time=node.heap(),tmr.time()
      print(M.format(sensor,payload:format(sensor.name)))
    else
      M.format(sensor)
    end
  elseif verbose then
    print(('--Sensor "%s" not found!'):format(sensor.name))
  end
  if cleanup then  -- release memory
    _G[sensor.name],package.loaded[sensor.name],sensor=nil,nil,nil
  end

  sensor=require('pms3003')
  if sensor.init(PMset) then
    sensor.read(false,false,function()
      if verbose then
        sensor.heap,sensor.time=node.heap(),tmr.time()
        print(M.format(sensor,payload:format(sensor.name)))
      else
        M.format(sensor)
      end
      if cleanup then  -- release memory
        _G[sensor.name],package.loaded[sensor.name],sensor=nil,nil,nil
      end
      if type(callBack)=='function' then callBack() end
    end)
  elseif verbose then
    print(('--Sensor "%s" not found!'):format(sensor.name))
    if cleanup then  -- release memory
      _G[sensor.name],package.loaded[sensor.name],sensor=nil,nil,nil
    end
    if type(callBack)=='function' then callBack() end
  end
end

return M
