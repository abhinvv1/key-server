# frozen_string_literal: true

require 'redis'
require 'securerandom'
require './redis_client'
require './constants'
require 'logger'

class KeyManager
  def initialize
    @redis = RedisClient.new.connection
    @logger = Logger.new(STDOUT)
  rescue Redis::CannotConnectError => e
    @logger.error("Failed to connect to Redis: #{e.message}")
    raise
  rescue StandardError => e
    @logger.error("Unexpected error during initialization: #{e.message}")
    raise
  end

  def generate_key
    key = SecureRandom.hex(16)
    set_key_with_expiry(key)
    key
  rescue Redis::BaseError => e
    @logger.error("Redis error generating key: #{e.message}")
    nil
  rescue StandardError => e
    @logger.error("Unexpected error generating key: #{e.message}")
    nil
  end

  def get_available_key
    key = @redis.spop(Constants::AVAILABLE_KEYS)
    return unless key

    if @redis.exists?("#{Constants::KEY_PREFIX}#{key}")
      set_key_as_blocked(key)
      key
    else
      delete_key(key)
      nil
    end
  rescue Redis::BaseError => e
    @logger.error("Redis error getting available key: #{e.message}")
    nil
  rescue StandardError => e
    @logger.error("Unexpected error getting available key: #{e.message}")
    nil
  end

  def unblock_key(key)
    return false unless key && @redis.exists?("#{Constants::KEY_PREFIX}#{key}")

    @redis.zrem(Constants::BLOCKED_KEYS_SORTED_SET, key)
    set_key_with_expiry(key)
    true
  rescue Redis::BaseError => e
    @logger.error("Redis error unblocking key: #{e.message}")
    false
  rescue StandardError => e
    @logger.error("Unexpected error unblocking key: #{e.message}")
    false
  end

  def delete_key(key)
    return false unless key

    @redis.multi do |multi|
      multi.del("#{Constants::KEY_PREFIX}#{key}")
      multi.srem(Constants::AVAILABLE_KEYS, key)
      multi.zrem(Constants::KEY_EXPIRY_SORTED_SET, key)
      multi.zrem(Constants::BLOCKED_KEYS_SORTED_SET, key)
    end
    true
  rescue Redis::BaseError => e
    @logger.error("Redis error deleting key: #{e.message}")
    false
  rescue StandardError => e
    @logger.error("Unexpected error deleting key: #{e.message}")
    false
  end

  def keep_alive(key)
    return false unless key && @redis.exists?("#{Constants::KEY_PREFIX}#{key}")
    set_key_with_expiry(key)
    true
  rescue Redis::BaseError => e
    @logger.error("Redis error keeping key alive: #{e.message}")
    false
  rescue StandardError => e
    @logger.error("Unexpected error keeping key alive: #{e.message}")
    false
  end

  def manage_keys
    loop do
      begin
        current_time = Time.now.to_i

        # Check and remove expired keys
        @redis.zrangebyscore(Constants::KEY_EXPIRY_SORTED_SET, "0", current_time).each do |key|
          delete_key(key)
        end

        # Unblock keys that have exceeded their block time
        @redis.zrangebyscore(Constants::BLOCKED_KEYS_SORTED_SET, "0", current_time).each do |key|
          @redis.zrem(Constants::BLOCKED_KEYS_SORTED_SET, key)
          set_key_with_expiry(key) if @redis.exists?("#{Constants::KEY_PREFIX}#{key}")
        end

        sleep 1
      rescue Redis::BaseError => e
        @logger.error("Redis error in manage_keys loop: #{e.message}")
        sleep 1
      rescue StandardError => e
        @logger.error("Unexpected error in manage_keys loop: #{e.message}")
        sleep 1
      end
    end
  end

  private

  def set_key_with_expiry(key)
    return false unless key
    expiry_time = Time.now.to_i + Constants::EXPIRY_TIME
    @redis.multi do |multi|
      multi.setex("#{Constants::KEY_PREFIX}#{key}", Constants::EXPIRY_TIME, 'available')
      multi.sadd(Constants::AVAILABLE_KEYS, key)
      multi.zadd(Constants::KEY_EXPIRY_SORTED_SET, expiry_time, key)
    end
    true
  rescue Redis::BaseError => e
    @logger.error("Redis error setting key with expiry: #{e.message}")
    false
  rescue StandardError => e
    @logger.error("Unexpected error setting key with expiry: #{e.message}")
    false
  end

  def set_key_as_blocked(key)
    return false unless key
    block_expiry_time = Time.now.to_i + Constants::BLOCK_TIME
    @redis.multi do |multi|
      multi.zadd(Constants::BLOCKED_KEYS_SORTED_SET, block_expiry_time, key)
      multi.zadd(Constants::KEY_EXPIRY_SORTED_SET, Time.now.to_i + Constants::EXPIRY_TIME, key)
    end
    true
  rescue Redis::BaseError => e
    @logger.error("Redis error setting key as blocked: #{e.message}")
    false
  rescue StandardError => e
    @logger.error("Unexpected error setting key as blocked: #{e.message}")
    false
  end
end