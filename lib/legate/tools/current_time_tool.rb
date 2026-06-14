# File: lib/legate/tools/current_time_tool.rb
# frozen_string_literal: true

require_relative '../tool'
require 'time'

module Legate
  module Tools
    # Returns the current date and time.
    #
    # Language models don't know the current time, so this is a common building
    # block for scheduling, "how long ago", and freshness checks. Returns UTC by
    # default; accepts "UTC", "local", or a fixed UTC offset (e.g. "+09:00").
    # Named IANA zones (e.g. "America/New_York") are intentionally not supported
    # to avoid a timezone-database dependency and process-global TZ mutation.
    class CurrentTime < Legate::Tool
      OFFSET_PATTERN = /\A[+-]\d{2}:?\d{2}\z/

      tool_name # inferred: :current_time
      tool_description 'Returns the current date and time (ISO 8601, epoch, and an optional custom format). ' \
                       'Accepts a timezone of "UTC" (default), "local", or a fixed UTC offset like "+09:00".'

      parameter :timezone, type: :string, required: false,
                           description: 'Timezone: "UTC" (default), "local", or a fixed offset such as "+05:30" or "-0800".'
      parameter :format, type: :string, required: false,
                         description: 'Optional strftime format (e.g. "%A, %B %-d, %Y"). Defaults to ISO 8601.'

      private

      def perform_execution(params, _context)
        now = Time.now.utc
        tz = params[:timezone].to_s.strip
        base = localize(now, tz)
        return { status: :error, error_message: unsupported_tz_message(tz) } unless base

        fmt = params[:format].to_s
        {
          status: :success,
          result: {
            iso8601: base.iso8601,
            formatted: fmt.empty? ? base.iso8601 : base.strftime(fmt),
            epoch: now.to_i,
            timezone: tz.empty? ? 'UTC' : tz
          }
        }
      rescue ArgumentError => e
        { status: :error, error_message: "Invalid format or timezone: #{e.message}" }
      end

      def localize(utc_now, zone)
        case zone.downcase
        when '', 'utc', 'z' then utc_now
        when 'local' then utc_now.getlocal
        else
          zone.match?(OFFSET_PATTERN) ? utc_now.getlocal(zone) : nil
        end
      end

      def unsupported_tz_message(zone)
        "Unsupported timezone '#{zone}'. Use 'UTC', 'local', or a fixed offset like '+09:00'."
      end
    end
  end
end
