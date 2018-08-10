# frozen_string_literal: true

module Coverband
  module Adapters
    class RedisStore < Base
      BASE_KEY = 'coverband2'

      def initialize(redis, opts = {})
        @redis = redis
        @ttl = opts[:ttl]
        @redis_namespace = opts[:redis_namespace]
      end

      def clear!
        @redis.smembers(base_key).each { |key| @redis.del("#{base_key}.#{key}") }
        @redis.del(base_key)
      end

      def base_key
        @base_key ||= [BASE_KEY, @redis_namespace].compact.join('.')
      end

      def log(msg)
        Coverband.configuration.logger.info(msg)
      end

      def save_report(report)
        log '@@@array'
        log Benchmark.measure {
          store_array(base_key, report.keys)
        }

        maps = []
        log '@@@each'
        log Benchmark.measure {
          report.each do |file, lines|
            # store_map("#{base_key}.#{file}", lines)
            #if create_map("#{base_key}.#{file}", lines).nil?
            #  Coverband.configuration.logger.info("FFF:::::: #{file}")
            #  Coverband.configuration.logger.info("LLL:::::: #{lines}")
            #end
            maps << create_map("#{base_key}.#{file}", lines)
          end
        }

        log '@@@store'
        log Benchmark.measure {
          store_maps(maps)
        }
      end

      def coverage
        data = {}
        redis.smembers(base_key).each do |key|
          data[key] = covered_lines_for_file(key)
        end
        data
      end

      def covered_files
        redis.smembers(base_key)
      end

      def covered_lines_for_file(file)
        @redis.hgetall("#{base_key}.#{file}")
      end

      private

      attr_reader :redis

      def store_map(key, values)
        unless values.empty?
          existing = redis.hgetall(key)
          # in redis all keys are strings
          values = Hash[values.map { |k, val| [k.to_s, val] }]
          values.merge!(existing) { |_k, old_v, new_v| old_v.to_i + new_v.to_i }
          # Coverband.configuration.logger.info("KEY:::::: #{key}")
          # Coverband.configuration.logger.info("VALUES:::::: #{values}")
          redis.mapped_hmset(key, values)
          redis.expire(key, @ttl) if @ttl
        end
      end

      def create_map(key, values)
        unless values.empty?
          existing = redis.hgetall(key)
          # in redis all keys are strings
          values = Hash[values.map { |k, val| [k.to_s, val] }]
          values.merge!(existing) { |_k, old_v, new_v| old_v.to_i + new_v.to_i }
          # Coverband.configuration.logger.info("KEY:::::: #{key}")
          # Coverband.configuration.logger.info("VALUES:::::: #{values}")
        end
        { key => values }
      end

      def store_maps(maps)
        # Coverband.configuration.logger.info("MAPS:::::: #{maps}")
        redis.pipelined do
          maps.each do |hash|
            key = hash.keys[0]
            values = hash[hash.keys[0]]
            next if values.empty?
            redis.mapped_hmset(key, values)
            redis.expire(key, @ttl) if @ttl
          end
        end
      end


      def store_array(key, values)
        redis.sadd(key, values) unless values.empty?
        redis.expire(key, @ttl) if @ttl
        values
      end
    end
  end
end
