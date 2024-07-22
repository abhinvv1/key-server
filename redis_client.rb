# frozen_string_literal: true

require 'redis'

class RedisClient

  def connection
    @redis = Redis.new(url: ENV['REDIS_URL'])
  end
end
