# frozen_string_literal: true

module Coverband
  module Adapters
    class RedisStore < Base
      BASE_KEY = 'coverband2'

      def initialize(redis, opts = {})
        @redis = redis
        @ttl             = opts[:ttl]
        @redis_namespace = opts[:redis_namespace]
      end

      def clear!
        @redis.smembers(base_key).each { |key| @redis.del("#{base_key}.#{key}") }
        @redis.del(base_key)
      end

      def base_key
        @base_key ||= [BASE_KEY, @redis_namespace].compact.join('.')
      end

      def save_report(report)
        store_array(base_key, report.keys)
        result_hash = {}
        report.each do |file, lines|
          m = merge_map("#{base_key}.#{file}", lines)
          result_hash.merge(m) unless m.nil?
        end
        store_hashes(base_key, result_hash)
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

      def merge_map(key, values)
        unless values.empty?
          existing = redis.hgetall(key)
          # in redis all keys are strings
          values = Hash[values.map { |k, val| [k.to_s, val] }]
          values.merge(existing) { |_k, old_v, new_v| old_v.to_i + new_v.to_i }
          values
        end
      end

      def store_hashes(key, values)
        redis.mapped_hmset(key, values)
        redis.expire(key, @ttl) if @ttl
      end

      def store_array(key, values)
        redis.sadd(key, values) unless values.empty?
        redis.expire(key, @ttl) if @ttl
        values
      end
    end
  end
end
