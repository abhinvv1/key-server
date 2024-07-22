# frozen_string_literal: true

require 'redis'
require 'securerandom'
require './redis_client'
require './constants'

class KeyManager
  def initialize
    @redis = RedisClient.new.connection
  end

  def generate_key
    key = SecureRandom.hex(16)
    set_key_with_expiry(key)
    key
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
  end

  def unblock_key(key)
    return false unless @redis.exists?("#{Constants::KEY_PREFIX}#{key}")

    @redis.zrem(Constants::BLOCKED_KEYS_SORTED_SET, key)
    set_key_with_expiry(key)
    true
  end

  def delete_key(key)
    @redis.multi do |multi|
      multi.del("#{Constants::KEY_PREFIX}#{key}")
      multi.srem(Constants::AVAILABLE_KEYS, key)
      multi.zrem(Constants::KEY_EXPIRY_SORTED_SET, key)
      multi.zrem(Constants::BLOCKED_KEYS_SORTED_SET, key)
    end
  end

  def keep_alive(key)
    return false unless @redis.exists?("#{Constants::KEY_PREFIX}#{key}")
    set_key_with_expiry(key)
    true
  end

  def manage_keys
    loop do
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
    end
  end

  private

  def set_key_with_expiry(key)
    expiry_time = Time.now.to_i + Constants::EXPIRY_TIME
    @redis.multi do |multi|
      multi.setex("#{Constants::KEY_PREFIX}#{key}", Constants::EXPIRY_TIME, 'available')
      multi.sadd(Constants::AVAILABLE_KEYS, key)
      multi.zadd(Constants::KEY_EXPIRY_SORTED_SET, expiry_time, key)
    end
  end

  def set_key_as_blocked(key)
    block_expiry_time = Time.now.to_i + Constants::BLOCK_TIME
    @redis.multi do |multi|
      multi.zadd(Constants::BLOCKED_KEYS_SORTED_SET, block_expiry_time, key)
      multi.zadd(Constants::KEY_EXPIRY_SORTED_SET, Time.now.to_i + Constants::EXPIRY_TIME, key)
    end
  end
end