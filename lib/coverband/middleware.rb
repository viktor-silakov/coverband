# frozen_string_literal: true
require 'benchmark'
module Coverband
  class Middleware
    def initialize(app)
      Coverband.configuration.logger.info("init middleware")
      @app = app
    end

    def log(msg)
      Coverband.configuration.logger.info(msg)
    end

    def call(env)

      log "$conf sampling"
      log Benchmark.measure {
        Coverband::Collectors::Base.instance.configure_sampling
      }.total

      log "$record coverage"
      log Benchmark.measure {
        Coverband::Collectors::Base.instance.record_coverage
      }.total
      @app.call(env)
    ensure
      log "$rePort coverage start"
      bench =  Benchmark.measure {
        Coverband::Collectors::Base.instance.report_coverage
      }.total

      log "$reporrt coverage: #{bench}"
    end
  end
end
