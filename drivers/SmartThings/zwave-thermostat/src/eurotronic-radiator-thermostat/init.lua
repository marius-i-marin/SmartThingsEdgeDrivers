-- Copyright 2022 SmartThings
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local capabilities = require "st.capabilities"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.ThermostatMode
local ThermostatMode = (require "st.zwave.CommandClass.ThermostatMode")({version=2})
--- @type st.zwave.CommandClass.Battery
local Battery = (require "st.zwave.CommandClass.Battery")({version=1})
--- @type st.zwave.CommandClass.SensorMultilevel
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({version=2})
--- @type st.zwave.CommandClass.ThermostatSetpoint
local ThermostatSetpoint = (require "st.zwave.CommandClass.ThermostatSetpoint")({version=1})

local EUROTRONIC_THERMOSTAT_FINGERPRINT_1 = {mfr = 0x0148, prod = 0x0003, model = 0x0001}
local EUROTRONIC_THERMOSTAT_FINGERPRINT_2 = {mfr = 0x0148, prod = 0x0003, model = 0x0004}

local function can_handle_eurotronic_radiator_thermostat(opts, driver, device, ...)
  return
    device:id_match(EUROTRONIC_THERMOSTAT_FINGERPRINT_1.mfr, EUROTRONIC_THERMOSTAT_FINGERPRINT_1.prod, EUROTRONIC_THERMOSTAT_FINGERPRINT_1.model) or
    device:id_match(EUROTRONIC_THERMOSTAT_FINGERPRINT_2.mfr, EUROTRONIC_THERMOSTAT_FINGERPRINT_2.prod, EUROTRONIC_THERMOSTAT_FINGERPRINT_2.model)
end

local function thermostat_mode_report_handler(self, device, cmd)
  local event = nil
  if (cmd.args.mode == ThermostatMode.mode.OFF) then
    event = capabilities.thermostatMode.thermostatMode.off()
  elseif (cmd.args.mode == ThermostatMode.mode.HEAT) then
    event = capabilities.thermostatMode.thermostatMode.heat()
  elseif (cmd.args.mode == ThermostatMode.mode.FULL_POWER) then
    event = capabilities.thermostatMode.thermostatMode.emergency_heat()
  end

  if (event ~= nil) then
    device:emit_event(event)
  end
end

local function set_thermostat_mode(driver, device, command)
  local modes = capabilities.thermostatMode.thermostatMode
  local mode = command.args.mode
  local modeValue = nil
  if (mode == modes.off.NAME) then
    modeValue = ThermostatMode.mode.OFF
  elseif (mode == modes.heat.NAME) then
    modeValue = ThermostatMode.mode.HEAT
  elseif (mode == modes.emergency_heat.NAME) then
    modeValue = ThermostatMode.mode.FULL_POWER
  end

  if (modeValue ~= nil) then
    device:send(ThermostatMode:Set({mode = modeValue}))

    local follow_up_poll = function()
      device:send(ThermostatMode:Get({}))
    end

    device.thread:call_with_delay(1, follow_up_poll)
  end
end

local set_emergency_heat_mode = function()
  return function(driver, device, command)
    set_thermostat_mode(driver, device,{args={mode=capabilities.thermostatMode.thermostatMode.emergency_heat.NAME}})
  end
end

local function do_refresh(self, device)
  device:send(ThermostatMode:Get({}))
  device:send(SensorMultilevel:Get({}))
  device:send(ThermostatSetpoint:Get({setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1}))
  device:send(Battery:Get({}))
end

local function device_added(self, device)
  -- In addition to 'OFF' and 'HEAT' modes, eurotronic also supports 'FULL_POWER',
  -- which doesn't have an equivalent in the capability.
  -- That's why, it's mapped to "emergency_heat"
  -- and 'supportedModes' event is sent right after device is added,
  -- instead of being a response to ThermostatModeSupported:Get().
  local supported_modes = {
    capabilities.thermostatMode.thermostatMode.off.NAME,
    capabilities.thermostatMode.thermostatMode.heat.NAME,
    capabilities.thermostatMode.thermostatMode.emergency_heat.NAME
  }
  device:emit_event(capabilities.thermostatMode.supportedThermostatModes(supported_modes, { visibility = { displayed = false } }))

  do_refresh(self, device)
end

local eurotronic_radiator_thermostat = {
  NAME = "eurotronic radiator thermostat",
  zwave_handlers = {
    [cc.THERMOSTAT_MODE] = {
      [ThermostatMode.REPORT] = thermostat_mode_report_handler
    }
  },
  capability_handlers = {
    [capabilities.thermostatMode.ID] = {
      [capabilities.thermostatMode.commands.setThermostatMode.NAME] = set_thermostat_mode,
      [capabilities.thermostatMode.commands.emergencyHeat.NAME] = set_emergency_heat_mode
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    }
  },
  lifecycle_handlers = {added = device_added},
  can_handle = can_handle_eurotronic_radiator_thermostat
}

return eurotronic_radiator_thermostat
