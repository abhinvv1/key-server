# frozen_string_literal: true

require 'redis'

class RedisClient

  def connection
    @redis = Redis.new(url: ENV['REDIS_URL'])
  rescue Redis::CannotConnectError => e
    @logger.error("Failed to connect to Redis: #{e.message}")
    raise
  end
end
