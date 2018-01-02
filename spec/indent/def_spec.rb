require 'spec_helper'

describe 'def indentation' do
  i <<~EOF
    def handle_call({:release_lock, key}, _from, state) do
      case get_lock(state, key) do
        nil ->
          {:reply, {:error, :already_unlocked}, state}

        _ ->
          new_state = delete_lock(state, key)
          {:reply, :ok, new_state}
      end
    end

    def
  EOF

#   i <<~EOF
#   defmodule Hello do
#     def hello do
#     end
# #{"\n" * 40}
#     def world do
#     end
#   end
#   EOF

  i <<~EOF
    @impl true
    def datetime_to_string(
          year,
          month,
          day,
          hour,
          minute,
          second,
          microsecond,
          _time_zone,
          zone_abbr,
          _utc_offset,
          _std_offset
        ) do
      "\#{year}-\#{month}-\#{day}" <>
        Calendar.ISO.time_to_string(hour, minute, second, microsecond) <> " \#{zone_abbr} (HE)"
    end
  EOF

  i <<~'EOF'
    defmodule Calendar.Holocene do
      # This calendar is used to test conversions between calendars.
      # It implements the Holocene calendar, which is based on the
      # Propleptic Gregorian calendar with every year + 10000.

      @behaviour Calendar

      def date(year, month, day) do
        %Date{year: year, month: month, day: day, calendar: __MODULE__}
      end

      def naive_datetime(year, month, day, hour, minute, second, microsecond \\ {0, 0}) do
        %NaiveDateTime{
          year: year,
          month: month,
          day: day,
          hour: hour,
          minute: minute,
          second: second,
          microsecond: microsecond,
          calendar: __MODULE__
        }
      end

      @impl true
      def date_to_string(year, month, day) do
        "#{year}-#{month}-#{day} (HE)"
      end

      @impl true
      def naive_datetime_to_string(year, month, day, hour, minute, second, microsecond) do
        "#{year}-#{month}-#{day}" <>
          Calendar.ISO.time_to_string(hour, minute, second, microsecond) <> " (HE)"
      end
  EOF

  i <<~EOF
    @impl true
    def day_rollover_relative_to_midnight_utc(), do: {0, 1}

    @impl true
    def naive_datetime_from_iso_days(entry) do
      {year, month, day, hour, minute, second, microsecond} =
        Calendar.ISO.naive_datetime_from_iso_days(entry)

      {year + 10000, month, day, hour, minute, second, microsecond}
    end
  EOF
end
