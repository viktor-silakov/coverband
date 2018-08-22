# frozen_string_literal: true

module Coverband
  module Reporters
    class ConsoleReport < Base
      def self.report(store, options = {})
        scov_style_report = super(store, options)

        scov_style_report.each_pair do |file, usage|
          Coverband.configuration.logger.debug "#{file}: #{usage}"
        end
        scov_style_report
      end
    end
  end
end
