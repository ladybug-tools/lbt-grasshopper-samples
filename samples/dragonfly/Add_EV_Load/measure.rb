# see the URL below for information on how to write OpenStudio measures
# http://nrel.github.io/OpenStudio-user-documentation/reference/measure_writing_guide/
# *******************************************************************************
# OpenStudio(R), Copyright (c) 2008-2020, Alliance for Sustainable Energy, LLC.
# All rights reserved.
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# (1) Redistributions of source code must retain the above copyright notice,
# this list of conditions and the following disclaimer.
#
# (2) Redistributions in binary form must reproduce the above copyright notice,
# this list of conditions and the following disclaimer in the documentation
# and/or other materials provided with the distribution.
#
# (3) Neither the name of the copyright holder nor the names of any contributors
# may be used to endorse or promote products derived from this software without
# specific prior written permission from the respective party.
#
# (4) Other than as required in clauses (1) and (2), distributions in any form
# of modifications or other derivative works may not use the "OpenStudio"
# trademark, "OS", "os", or any other confusingly similar designation without
# specific prior written permission from Alliance for Sustainable Energy, LLC.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDER(S) AND ANY CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
# THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER(S), ANY CONTRIBUTORS, THE
# UNITED STATES GOVERNMENT, OR THE UNITED STATES DEPARTMENT OF ENERGY, NOR ANY OF
# THEIR EMPLOYEES, BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT
# OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
# STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
# *******************************************************************************

require 'csv'
require 'matrix'
# start the measure
class AddEVLoad < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    return 'Add_EV_Load'
  end

  # human readable description
  def description
    return 'This measure adds a load associated with charging of electric vehicles (EVs) to a building in URBANopt. EV load profiles were generated in EVI-Pro for specific building types. This measure allows running of customized load profiles for buildings in the Pena Station Next project, and also for generating typical charging load profiles based on the location type (home, public, or office).'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'This measure adds an EV charging load to a building model. Load profiles for EV charging were generated in EVI-Pro. Different options are available for charging control type and charging behavior.'
  end

  # Note: If a DC Fast Charger at the PSN site is the intended option, the charging behavior and control choices are ignored. Thus far, there is one load profile for a DC fast charger; not different ones for different bldgs.
  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    # Make an argument for the charging flexibility options (workplace charging only).
    charge_delay_chs = OpenStudio::StringVector.new
    charge_delay_chs << 'Max Delay'
    charge_delay_chs << 'Min Delay'
    charge_delay_chs << 'Min Power'

    delay_type = OpenStudio::Measure::OSArgument.makeChoiceArgument('delay_type', charge_delay_chs, true)
    delay_type.setDisplayName('Charging Flexibility Option')
    delay_type.setDefaultValue('Min Delay')
    args << delay_type

    # Make an argument for the consumer charging behavior parameter.
    consumer_charge_chs = OpenStudio::StringVector.new
    consumer_charge_chs << 'Business as Usual'
    consumer_charge_chs << 'Free Workplace Charging at Project Site'
    consumer_charge_chs << 'Free Workplace Charging Across Metro Area'

    charge_behavior = OpenStudio::Measure::OSArgument.makeChoiceArgument('charge_behavior', consumer_charge_chs, true)
    charge_behavior.setDisplayName('Consumer Charging Behavior')
    charge_behavior.setDefaultValue('Business as Usual')
    args << charge_behavior

    # Make a vector for the charging station type argument.
    chg_station_type_chs = OpenStudio::StringVector.new
    chg_station_type_chs << 'Typical Home'
    chg_station_type_chs << 'Typical Public'
    chg_station_type_chs << 'Typical Work'

    # Make an argument for charging station type.
    chg_station_type = OpenStudio::Measure::OSArgument.makeChoiceArgument('chg_station_type', chg_station_type_chs, true)
    chg_station_type.setDisplayName('Charging Station Type')
    chg_station_type.setDefaultValue('Typical Public')
    args << chg_station_type

    # Make an argument for the % of vehicles parked at the building that are EVs.
    ev_percent = OpenStudio::Measure::OSArgument.makeDoubleArgument('ev_percent', true)
    ev_percent.setDisplayName('Percent of Vehicles Parked at Building That Are EVs')
    ev_percent.setDefaultValue(1.0)
    args << ev_percent

    return args
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # Assign the user arguments to variables.
    delay_type = runner.getStringArgumentValue('delay_type', user_arguments)
    charge_behavior = runner.getStringArgumentValue('charge_behavior', user_arguments)
    chg_station_type = runner.getStringArgumentValue('chg_station_type', user_arguments)
    ev_percent = runner.getDoubleArgumentValue('ev_percent', user_arguments)

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    if ev_percent < 0 || ev_percent > 100
      runner.registerError('Percent of vehicles on site that are electric is outside of acceptable bounds. Please choose a value between 0 and 100.')
      return false
    end

    # Set file name based on arguments selected and then choose the DOW within schedule selection.
    # Set key based on user-selected charging behavior.
    if charge_behavior == 'Business as Usual'
      charge_key = 1
      runner.registerInfo("charge key = #{charge_key}")
    elsif charge_behavior == 'Free Workplace Charging at Project Site'
      charge_key = 2
      runner.registerInfo("charge key = #{charge_key}")
    else
      charge_key = 3
      runner.registerInfo("charge key = #{charge_key}")
    end

    # Set key based on user-selected charging flexibility.
    if delay_type == 'Min Delay'
      flex_key = 1
      runner.registerInfo("flex key = #{flex_key}")
    elsif delay_type == 'Max Delay'
      flex_key = 2
      runner.registerInfo("flex key = #{flex_key}")
    else
      flex_key = 3
      runner.registerInfo("flex key = #{flex_key}")
    end

    file_path = "#{__dir__}/resources/"

    # Sets key based on charging station type, for general charging load profiles. Will use this to average columns appropriately.
    if chg_station_type == 'Typical Home'
      chg_station_key = 1
      runner.registerInfo("charge station key = #{chg_station_key}")
    elsif chg_station_type == 'Typical Work'
      chg_station_key = 2
      runner.registerInfo("charge station key = #{chg_station_key}")
    elsif chg_station_type == 'Typical Public'
      chg_station_key = 3
      runner.registerInfo("charge station key = #{chg_station_key}")
    end

    # Creating a schedule:ruleset
    ev_sch = OpenStudio::Model::ScheduleRuleset.new(model)
    ev_sch.setName('EV Charging Power Draw')

    # Create a schedule:ruleset for DC fast charging.
    ev_sch_fast = OpenStudio::Model::ScheduleRuleset.new(model)
    ev_sch_fast.setName('EV DC Fast Charging Power Draw')

    # Create arrays of desired values
    public_indices = [0, 1, 2, 3, 4, 5, 6, 8, 9, 10, 11, 12, 13, 14, 52, 53, 54, 57, 58, 60, 61, 62, 63, 64, 65, 81, 99, 100, 102]
    work_indices = [7, 19, 20, 27, 28, 29, 30, 31, 32, 36, 37, 42, 43, 44, 46, 50, 51, 55, 69, 70, 71, 86, 88, 91, 92, 93]
    home_indices = [15, 16, 17, 18, 21, 22, 23, 24, 25, 26, 33, 34, 35, 38, 39, 40, 41, 45, 47, 48, 49, 56, 59, 66, 67, 68, 72, 73, 74, 75, 76, 77, 78, 79, 80, 82, 83, 84, 85, 85, 87, 89, 90, 94, 95, 96, 97, 98, 101]

    # The load profiles referenced were generated based on an assumption of 50% of passenger vehicles being EVs.
    assumed_percent = 50

    # Read in the three necessary files, for the typical PSN case (all PSN bldgs, including fast chargers).
    # Read in wkday load profiles.
    dow_key = 1
    file_name = "chg#{charge_key}_dow#{dow_key}_flex#{flex_key}.csv"
    wkday_load = CSV.read("#{file_path}/#{file_name}", headers: false, converters: :all)
    wkday_load = wkday_load.to_a # Convert to an array.
    wkday_load = wkday_load.transpose
    # Read in Saturday load profiles.
    dow_key = 2
    file_name = "chg#{charge_key}_dow#{dow_key}_flex#{flex_key}.csv"
    sat_load = CSV.read("#{file_path}/#{file_name}", headers: false, converters: :all)
    sat_load = sat_load.to_a # Convert to an array.
    sat_load = sat_load.transpose
    # Read in Sunday load profiles.
    dow_key = 3
    file_name = "chg#{charge_key}_dow#{dow_key}_flex#{flex_key}.csv"
    sun_load = CSV.read("#{file_path}/#{file_name}", headers: false, converters: :all)
    sun_load = sun_load.to_a # Convert to an array.
    sun_load = sun_load.transpose

    # For non-PSN analysis, select which load profile is needed based on the charging station key.

    if chg_station_key == 1
      indices = home_indices
    elsif chg_station_key == 2
      indices = work_indices
    elsif chg_station_key == 3
      indices = public_indices
    end

    # Popualte the average weekday load for non PSN case. The load profiles used in this case are averaged based on the selected charging station type,(given the selected charging flexibility option and charging behavior option), and scaled for the percent of vehicles that are EVs.
    if chg_station_type != 'Pena Station Next Analysis' && chg_station_type != 'Pena Station Next Analysis--DC Fast Charger'
      wkday_load_sel = wkday_load.values_at(*indices)
      avg_load_wkday = []
      wkday_load_sel = wkday_load_sel.transpose
      for i in 0..wkday_load[0].length - 1
        avg_load_wkday[i] = (wkday_load_sel[i].reduce(0, :+) / wkday_load_sel[i].length) * ev_percent / assumed_percent # Scale profiles generated from 50% EV scenario by % of vehicles that are EVs.
      end

      wkday_max_load = avg_load_wkday.max

      # Populate the average Saturday load.
      sat_load_sel = sat_load.values_at(*indices)
      avg_load_sat = []
      sat_load_sel = sat_load_sel.transpose
      for i in 0..sat_load[0].length - 1
        avg_load_sat[i] = (sat_load_sel[i].reduce(0, :+) / sat_load_sel[i].length) * ev_percent / assumed_percent # Scale profiles generated from 50% EV scenario by % of vehicles that are EVs.
      end

      sat_max_load = avg_load_sat.max

      # Populate the average Sunday load.
      sun_load_sel = sun_load.values_at(*indices)
      avg_load_sun = []
      sun_load_sel = sun_load_sel.transpose
      for i in 0..sun_load[0].length - 1
        avg_load_sun[i] = (sun_load_sel[i].reduce(0, :+) / sun_load_sel[i].length) * ev_percent / assumed_percent # Scale profiles generated from 50% EV scenario by % of vehicles that are EVs.
      end

      sun_max_load = avg_load_sun.max

      # Calculate the overall maximum load
      max_load = [wkday_max_load, sat_max_load, sun_max_load].max

      # Normalize each load profile based on the overall maximum load.

      avg_load_wkday_norm = avg_load_wkday.map { |value| value / max_load }
      avg_load_sat_norm = avg_load_sat.map { |value| value / max_load }
      avg_load_sun_norm = avg_load_sun.map { |value| value / max_load }

    end

    # Create schedules for regular EV charging.
    # Uses Sunday schedule for winter design day.
    if chg_station_type != 'Pena Station Next Analysis--DC Fast Charger'
      ev_sch_winter = OpenStudio::Model::ScheduleDay.new(model)
      ev_sch.setWinterDesignDaySchedule(ev_sch_winter)
      ev_sch.winterDesignDaySchedule.setName('EV Charging Winter Design Day')
      # Loop through all the values and add to schedule
      avg_load_sun_norm.each_with_index do |value, i| # Reading in the data from the array created from the csv file, with the values normalized to maximum power draw.
        time = OpenStudio::Time.new(0, 0, (i + 1) * 15, 0) # OpenStudio::Time.new(day,hr of day, minute of hr, seconds of hr?)
        ev_sch.winterDesignDaySchedule.addValue(time, value)
      end
      runner.registerInfo(" WDD schedule = #{avg_load_wkday_norm}")
      # ...repeat for all 24 hrs (or whatever granularity)

      # Summer design day. Uses weekday schedule for summer design day.
      ev_sch_summer = OpenStudio::Model::ScheduleDay.new(model)
      ev_sch.setSummerDesignDaySchedule(ev_sch_summer)
      ev_sch.summerDesignDaySchedule.setName('EV Charging Summer Design Day')
      # Loop through all the values and add to schedule
      avg_load_wkday_norm.each_with_index do |value, i|
        time = OpenStudio::Time.new(0, 0, (i + 1) * 15, 0) # OpenStudio::Time.new(day,hr of day, minute of hr, seconds of hr?)
        ev_sch.summerDesignDaySchedule.addValue(time, value)
      end

      # Default day (use this for weekdays)
      ev_sch.defaultDaySchedule.setName('EV Charging Default')
      # Loop through all the values and add to schedule
      avg_load_wkday_norm.each_with_index do |value, i|
        time = OpenStudio::Time.new(0, 0, (i + 1) * 15, 0) # OpenStudio::Time.new(day,hr of day, minute of hr, seconds of hr?)
        ev_sch.defaultDaySchedule.addValue(time, value)
      end

      # Saturday
      ev_sch_sat_rule = OpenStudio::Model::ScheduleRule.new(ev_sch)
      ev_sch_sat_rule.setName('ev_sch_sat_rule')
      ev_sch_sat_rule.setApplySaturday(true)
      ev_sch_sat = ev_sch_sat_rule.daySchedule
      ev_sch_sat.setName('EV Charging Sat')
      # Loop through all the values and add to schedule
      avg_load_sat_norm.each_with_index do |value, i|
        time = OpenStudio::Time.new(0, 0, (i + 1) * 15, 0) # OpenStudio::Time.new(day,hr of day, minute of hr, seconds of hr?)
        ev_sch_sat.addValue(time, value)
      end

      # Sunday
      ev_sch_sun_rule = OpenStudio::Model::ScheduleRule.new(ev_sch)
      ev_sch_sun_rule.setName('ev_sch_sun_rule')
      ev_sch_sun_rule.setApplySunday(true)
      ev_sch_sun = ev_sch_sun_rule.daySchedule
      ev_sch_sun.setName('EV Charging Sun')
      # Loop through all the values and add to schedule
      avg_load_sun_norm.each_with_index do |value, i|
        time = OpenStudio::Time.new(0, 0, (i + 1) * 15, 0)
        ev_sch_sun.addValue(time, value)
      end
    end

    if chg_station_type != 'Pena Station Next Analysis--DC Fast Charger'

      # Adding an EV charger definition and instance for the regular EV charging.
      ev_charger_def = OpenStudio::Model::ExteriorFuelEquipmentDefinition.new(model)
      ev_charger_level = max_load * 1000 # Converting from kW to watts
      ev_charger_def.setName("#{ev_charger_level} w EV Charging Definition")
      ev_charger_def.setDesignLevel(ev_charger_level)

      # creating EV charger object for the regular EV charging.
      ev_charger = OpenStudio::Model::ExteriorFuelEquipment.new(ev_charger_def, ev_sch)
      ev_charger.setName("#{ev_charger_level} w EV Charger")
      ev_charger.setFuelType('Electricity')
      ev_charger.setEndUseSubcategory('Electric Vehicles')
      runner.registerInfo("multiplier (kW) = #{max_load}}")
    end
    return true
  end
end
# register the measure to be used by the application
AddEVLoad.new.registerWithApplication
